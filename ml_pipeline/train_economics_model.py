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

df = pd.read_csv(csv_path)

features = ['distance_km', 'duration_min', 'congestion_ratio', 'vehicle_type', 'booked_seats', 'fuel_price']
targets = ['target_fuel_liters', 'target_maintenance_pkr', 'target_fare_pkr']

X = df[features].values.astype(np.float32)
y = df[targets].values.astype(np.float32)

# Compute Min-Max Normalization bounds
norm_params = {
    'features': {f: {'min': float(df[f].min()), 'max': float(df[f].max())} for f in features},
    'targets': {t: {'min': float(df[t].min()), 'max': float(df[t].max())} for t in targets}
}

norm_path = os.path.join(assets_ml_dir, 'economics_normalization.json')
with open(norm_path, 'w') as f:
    json.dump(norm_params, f, indent=2)
print(f"✅ Saved normalization bounds to {norm_path}")

X_norm = np.zeros_like(X)
for i, f in enumerate(features):
    f_min, f_max = norm_params['features'][f]['min'], norm_params['features'][f]['max']
    X_norm[:, i] = (X[:, i] - f_min) / (f_max - f_min + 1e-7)

y_norm = np.zeros_like(y)
for i, t in enumerate(targets):
    t_min, t_max = norm_params['targets'][t]['min'], norm_params['targets'][t]['max']
    y_norm[:, i] = (y[:, i] - t_min) / (t_max - t_min + 1e-7)

# Multi-Output Dense Architecture
inputs = tf.keras.Input(shape=(len(features),), name='features_input')
x = tf.keras.layers.Dense(64, activation='relu')(inputs)
x = tf.keras.layers.Dense(32, activation='relu')(x)
x = tf.keras.layers.Dense(16, activation='relu')(x)
outputs = tf.keras.layers.Dense(len(targets), activation='linear', name='economics_output')(x)

model = tf.keras.Model(inputs=inputs, outputs=outputs)
model.compile(optimizer=tf.keras.optimizers.Adam(learning_rate=0.003), loss='mse', metrics=['mae'])
model.summary()

model.fit(
    X_norm,
    y_norm,
    epochs=40,
    batch_size=32,
    validation_split=0.15,
    verbose=1
)

# Export directly to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

tflite_path = os.path.join(assets_ml_dir, 'economics_model.tflite')
with open(tflite_path, 'wb') as f:
    f.write(tflite_model)

print(f"✅ Exported {tflite_path} ({len(tflite_model)/1024:.2f} KB)")
