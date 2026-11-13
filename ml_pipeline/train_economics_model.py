import json
import os
import numpy as np
import pandas as pd
import tensorflow as tf

current_dir = os.path.dirname(__file__)
csv_path = os.path.join(current_dir, 'economics_data.csv')
project_root = os.path.abspath(os.path.join(current_dir, '..'))
assets_ml_dir = os.path.join(project_root, 'assets', 'ml')
os.makedirs(assets_ml_dir, exist_ok=True)

if not os.path.exists(csv_path):
    raise FileNotFoundError(f"Could not find {csv_path}. Run generate_economics_data.py first.")

df = pd.read_csv(csv_path)
print(f"Loaded {len(df)} samples from {csv_path}")

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

# Split train/test (85% train/val, 15% held-out test) using numpy
np.random.seed(42)
shuffled_idx = np.random.permutation(len(df))
test_size = int(len(df) * 0.15)
test_idx = shuffled_idx[:test_size]
train_idx = shuffled_idx[test_size:]
train_df = df.iloc[train_idx]
test_df = df.iloc[test_idx]

# Compute Min-Max Normalization bounds from entire dataset
norm_params = {
    'features': {f: {'min': float(df[f].min()), 'max': float(df[f].max())} for f in features},
    'targets': {t: {'min': float(df[t].min()), 'max': float(df[t].max())} for t in targets}
}

norm_path = os.path.join(assets_ml_dir, 'economics_normalization.json')
with open(norm_path, 'w') as f:
    json.dump(norm_params, f, indent=2)
print(f"✅ Saved normalization bounds to {norm_path}")

def normalize_features(data_df):
    X_raw = data_df[features].values.astype(np.float32)
    X_n = np.zeros_like(X_raw)
    for i, f in enumerate(features):
        f_min = norm_params['features'][f]['min']
        f_max = norm_params['features'][f]['max']
        X_n[:, i] = (X_raw[:, i] - f_min) / (f_max - f_min + 1e-7)
    return X_n

def normalize_targets(data_df):
    y_raw = data_df[targets].values.astype(np.float32)
    y_n = np.zeros_like(y_raw)
    for i, t in enumerate(targets):
        t_min = norm_params['targets'][t]['min']
        t_max = norm_params['targets'][t]['max']
        y_n[:, i] = (y_raw[:, i] - t_min) / (t_max - t_min + 1e-7)
    return y_n

X_train_norm = normalize_features(train_df)
y_train_norm = normalize_targets(train_df)

X_test_norm = normalize_features(test_df)
y_test_raw = test_df[targets].values.astype(np.float32)

# Multi-Output Dense Neural Network Architecture
inputs = tf.keras.Input(shape=(len(features),), name='features_input')
x = tf.keras.layers.Dense(64, activation='relu')(inputs)
x = tf.keras.layers.Dense(64, activation='relu')(x)
x = tf.keras.layers.Dense(32, activation='relu')(x)
x = tf.keras.layers.Dense(16, activation='relu')(x)
outputs = tf.keras.layers.Dense(len(targets), activation='linear', name='economics_output')(x)

model = tf.keras.Model(inputs=inputs, outputs=outputs)
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.002),
    loss='mse',
    metrics=['mae']
)
model.summary()

history = model.fit(
    X_train_norm,
    y_train_norm,
    epochs=50,
    batch_size=32,
    validation_split=0.15,
    verbose=1
)

# Evaluate on Held-Out Test Set (Denormalized Real Units)
test_preds_norm = model.predict(X_test_norm)
test_preds = np.zeros_like(test_preds_norm)
for i, t in enumerate(targets):
    t_min = norm_params['targets'][t]['min']
    t_max = norm_params['targets'][t]['max']
    test_preds[:, i] = test_preds_norm[:, i] * (t_max - t_min) + t_min

fuel_mae = np.mean(np.abs(test_preds[:, 0] - y_test_raw[:, 0]))
maint_mae = np.mean(np.abs(test_preds[:, 1] - y_test_raw[:, 1]))
fare_mae = np.mean(np.abs(test_preds[:, 2] - y_test_raw[:, 2]))

print("\n" + "=" * 55)
print("📊 HELD-OUT TEST EVALUATION RESULTS:")
print(f"  • Fuel Burn MAE:         {fuel_mae:.4f} Liters")
print(f"  • Maintenance Wear MAE:  PKR {maint_mae:.2f}")
print(f"  • Sweet-Spot Fare MAE:   PKR {fare_mae:.2f}")
print("=" * 55 + "\n")

# Export quantized TFLite model
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

tflite_path = os.path.join(assets_ml_dir, 'economics_model.tflite')
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)

print(f"✅ Exported {tflite_path} ({len(tflite_model)/1024:.2f} KB)")
