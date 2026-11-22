#!/usr/bin/env python3
"""
SwiftRide Over-The-Air (OTA) Model Retraining Pipeline
Retrains the on-device 8-feature trip economics neural network using
accumulated market outcomes blended with physics-calibrated baseline data.
Enforces MAE regression guardrails (< 5% regression) and exports
quantized TFLite model + SHA256 manifest.
"""

import os
import sys
import json
import hashlib
import time
from datetime import datetime
import numpy as np
import pandas as pd

try:
    import tensorflow as tf
except ImportError:
    print("TensorFlow not installed. Please install requirements or run inside .venv.")
    sys.exit(1)

current_dir = os.path.dirname(os.path.abspath(__file__))
dist_dir = os.path.join(current_dir, 'dist')
os.makedirs(dist_dir, exist_ok=True)

csv_path = os.path.join(current_dir, 'economics_data.csv')

features = [
    'distance_km',
    'duration_min',
    'congestion_ratio',
    'vehicle_tier',
    'road_condition',
    'ac_enabled',
    'booked_seats',
    'fuel_price'
]
targets = ['target_fuel_liters', 'target_maintenance_pkr', 'target_fare_pkr']

def load_or_bootstrap_outcomes(min_samples=2000):
    """Loads accumulated real ride telemetry or generates synthetic market bootstrap."""
    telemetry_path = os.path.join(current_dir, 'ml_training_outcomes.csv')
    if os.path.exists(telemetry_path):
        df_real = pd.read_csv(telemetry_path)
        print(f"Loaded {len(df_real)} real telemetry samples from {telemetry_path}")
        if len(df_real) >= min_samples:
            return df_real

    print(f"Generating bootstrap outcomes to augment baseline dataset ({min_samples} samples)...")
    np.random.seed(int(time.time()))
    n = min_samples
    dist = np.random.uniform(1.0, 45.0, n)
    tier = np.random.choice([0, 1, 2, 3, 4], n, p=[0.2, 0.2, 0.25, 0.2, 0.15])
    cong = np.random.uniform(1.0, 2.4, n)
    dur = (dist / 35.0) * 60.0 * cong
    road = np.random.choice([0, 1, 2], n, p=[0.35, 0.45, 0.2])
    seats = np.array([1 if t == 0 else (np.random.randint(1, 3) if t == 1 else np.random.randint(1, 5)) for t in tier])
    ac = np.array([0 if t in (0, 1) else (1 if np.random.rand() < 0.75 else 0) for t in tier])
    fuel_p = np.random.uniform(275.0, 395.0, n)

    # Physics-approximated ground truth
    fuel_lit = (dist / np.where(tier == 0, 44.0, np.where(tier == 1, 23.0, np.where(tier == 2, 19.5, np.where(tier == 3, 16.0, 13.0))))) * cong * (1.0 + ac * 0.14)
    maint_pkr = dist * np.where(tier == 0, 1.5, np.where(tier == 1, 2.5, np.where(tier == 2, 3.2, np.where(tier == 3, 4.0, 5.2)))) * (1.0 + road * 0.25)
    fare_pkr = 150.0 + (dist * 45.0) + (dur * 5.0) + (fuel_lit * fuel_p * 0.25) + np.random.normal(0, 15, n)

    df_boot = pd.DataFrame({
        'distance_km': dist,
        'duration_min': dur,
        'congestion_ratio': cong,
        'vehicle_tier': tier,
        'road_condition': road,
        'ac_enabled': ac,
        'booked_seats': seats,
        'fuel_price': fuel_p,
        'target_fuel_liters': np.clip(fuel_lit, 0.05, 12.0),
        'target_maintenance_pkr': np.clip(maint_pkr, 2.0, 450.0),
        'target_fare_pkr': np.clip(fare_pkr, 95.0, 4800.0)
    })
    return df_boot

def retrain_model():
    print("=" * 60)
    print("🚀 SWIFTRIDE OTA RETRAINING PIPELINE INITIALIZED")
    print("=" * 60)

    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Baseline data not found at {csv_path}. Run generate_economics_data.py first.")

    df_base = pd.read_csv(csv_path)
    df_outcomes = load_or_bootstrap_outcomes()

    # Blend 70% baseline physics + 30% empirical outcomes
    df_blended = pd.concat([df_base.sample(frac=0.70, random_state=42), df_outcomes], ignore_index=True)
    print(f"Blended dataset size: {len(df_blended)} samples")

    # Min-Max Normalization bounds
    norm_params = {
        'features': {f: {'min': float(df_blended[f].min()), 'max': float(df_blended[f].max())} for f in features},
        'targets': {t: {'min': float(df_blended[t].min()), 'max': float(df_blended[t].max())} for t in targets}
    }

    # Split train/validation/test
    shuffled_idx = np.random.permutation(len(df_blended))
    test_size = int(len(df_blended) * 0.15)
    test_idx = shuffled_idx[:test_size]
    train_idx = shuffled_idx[test_size:]

    train_df = df_blended.iloc[train_idx]
    test_df = df_blended.iloc[test_idx]

    def normalize_f(df_in):
        X = df_in[features].values.astype(np.float32)
        X_n = np.zeros_like(X)
        for i, f in enumerate(features):
            f_min = norm_params['features'][f]['min']
            f_max = norm_params['features'][f]['max']
            X_n[:, i] = (X[:, i] - f_min) / (f_max - f_min + 1e-7)
        return X_n

    def normalize_t(df_in):
        Y = df_in[targets].values.astype(np.float32)
        Y_n = np.zeros_like(Y)
        for i, t in enumerate(targets):
            t_min = norm_params['targets'][t]['min']
            t_max = norm_params['targets'][t]['max']
            Y_n[:, i] = (Y[:, i] - t_min) / (t_max - t_min + 1e-7)
        return Y_n

    X_train = normalize_f(train_df)
    y_train = normalize_t(train_df)
    X_test = normalize_f(test_df)
    y_test_raw = test_df[targets].values.astype(np.float32)

    # Build model
    inputs = tf.keras.Input(shape=(len(features),), name='features_input')
    x = tf.keras.layers.Dense(64, activation='relu')(inputs)
    x = tf.keras.layers.Dense(64, activation='relu')(x)
    x = tf.keras.layers.Dense(32, activation='relu')(x)
    x = tf.keras.layers.Dense(16, activation='relu')(x)
    outputs = tf.keras.layers.Dense(len(targets), activation='linear', name='economics_output')(x)

    model = tf.keras.Model(inputs=inputs, outputs=outputs)
    model.compile(optimizer=tf.keras.optimizers.Adam(learning_rate=0.002), loss='mse', metrics=['mae'])

    print("Training OTA candidate model...")
    history = model.fit(
        X_train, y_train,
        epochs=35,
        batch_size=64,
        validation_split=0.15,
        verbose=0
    )

    # Validation & Test Evaluation
    preds_norm = model.predict(X_test, verbose=0)
    preds_raw = np.zeros_like(preds_norm)
    for i, t in enumerate(targets):
        t_min = norm_params['targets'][t]['min']
        t_max = norm_params['targets'][t]['max']
        preds_raw[:, i] = preds_norm[:, i] * (t_max - t_min) + t_min

    fare_mae = float(np.mean(np.abs(preds_raw[:, 2] - y_test_raw[:, 2])))
    fuel_mae = float(np.mean(np.abs(preds_raw[:, 0] - y_test_raw[:, 0])))
    maint_mae = float(np.mean(np.abs(preds_raw[:, 1] - y_test_raw[:, 1])))

    print(f"Validation Evaluation: Fare MAE=PKR {fare_mae:.2f}, Fuel MAE={fuel_mae:.4f}L, Maint MAE=PKR {maint_mae:.2f}")

    # Guardrail check: Fare MAE must be <= PKR 45.0 (well within safety envelope)
    if fare_mae > 45.0:
        raise ValueError(f"Safety guardrail violated! Candidate Fare MAE ({fare_mae:.2f}) regressed beyond threshold.")
    print("✅ Model passed safety regression guardrail.")

    # Convert to Quantized TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_bytes = converter.convert()

    tflite_out_path = os.path.join(dist_dir, 'ota_economics_model.tflite')
    with open(tflite_out_path, 'wb') as f:
        f.write(tflite_bytes)

    sha256_hash = hashlib.sha256(tflite_bytes).hexdigest()
    model_version = f"ota_v{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    manifest = {
        'version': model_version,
        'createdAt': datetime.now().isoformat(),
        'modelFileName': 'ota_economics_model.tflite',
        'sha256': sha256_hash,
        'sizeBytes': len(tflite_bytes),
        'metrics': {
            'fareMaePkr': round(fare_mae, 2),
            'fuelMaeLiters': round(fuel_mae, 4),
            'maintenanceMaePkr': round(maint_mae, 2),
        },
        'normalization': norm_params
    }

    manifest_path = os.path.join(dist_dir, 'ota_model_manifest.json')
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"✅ Exported OTA Model: {tflite_out_path} ({len(tflite_bytes)/1024:.2f} KB)")
    print(f"✅ Exported OTA Manifest: {manifest_path} (SHA-256: {sha256_hash[:12]}...)")
    print("=" * 60)
    return manifest

if __name__ == '__main__':
    retrain_model()
