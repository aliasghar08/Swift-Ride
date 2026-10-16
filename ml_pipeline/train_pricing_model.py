import json
import os
import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

def train_and_export():
    print(f"TensorFlow version: {tf.__version__}")
    data_path = "ml_pipeline/ride_data.csv"
    if not os.path.exists(data_path):
        raise FileNotFoundError(f"Could not find {data_path}. Run generate_synthetic_data.py first.")

    df = pd.read_csv(data_path)
    print(f"Loaded {len(df)} samples from {data_path}")

    features = ["distance_km", "time_of_day_hours", "is_raining", "traffic_multiplier"]
    target = "final_accepted_bid"

    # Train/Validation/Test split (80% train, 10% val, 10% test)
    np.random.seed(42)
    indices = np.random.permutation(len(df))
    train_end = int(0.8 * len(df))
    val_end = int(0.9 * len(df))

    train_idx = indices[:train_end]
    val_idx = indices[train_end:val_end]
    test_idx = indices[val_end:]

    train_df = df.iloc[train_idx].copy()
    val_df = df.iloc[val_idx].copy()
    test_df = df.iloc[test_idx].copy()

    # Calculate normalization parameters strictly on the training set
    norm_params = {}
    for col in features:
        min_val = float(train_df[col].min())
        max_val = float(train_df[col].max())
        mean_val = float(train_df[col].mean())
        std_val = float(train_df[col].std())
        norm_params[col] = {
            "min": min_val,
            "max": max_val,
            "mean": mean_val,
            "std": std_val if std_val > 0 else 1.0
        }

    print("\nFeature Normalization Parameters (fitted on Train):")
    print(json.dumps(norm_params, indent=2))

    # Min-Max Normalization to [0, 1] range for clean neural network inputs and portable mobile inference
    def normalize_features(data):
        norm_data = np.zeros((len(data), len(features)), dtype=np.float32)
        for i, col in enumerate(features):
            p = norm_params[col]
            norm_data[:, i] = (data[col].values - p["min"]) / (p["max"] - p["min"])
        return norm_data

    x_train = normalize_features(train_df)
    y_train = train_df[target].values.astype(np.float32)

    x_val = normalize_features(val_df)
    y_val = val_df[target].values.astype(np.float32)

    x_test = normalize_features(test_df)
    y_test = test_df[target].values.astype(np.float32)

    # Lightweight Sequential Neural Network for mobile regression
    model = keras.Sequential([
        layers.Input(shape=(len(features),), dtype=tf.float32, name="input_features"),
        layers.Dense(32, activation="relu", name="dense_1"),
        layers.Dense(16, activation="relu", name="dense_2"),
        layers.Dense(1, activation="linear", name="predicted_bid")
    ])

    optimizer = keras.optimizers.Adam(learning_rate=0.01)
    model.compile(optimizer=optimizer, loss="mean_squared_error", metrics=["mae", "mse"])
    model.summary()

    # Train for 50 epochs
    epochs = 50
    history = model.fit(
        x_train, y_train,
        validation_data=(x_val, y_val),
        epochs=epochs,
        batch_size=32,
        verbose=1
    )

    # Evaluate on held-out test set
    test_loss, test_mae, test_mse = model.evaluate(x_test, y_test, verbose=0)
    print(f"\nHeld-out Test Evaluation: MAE = PKR {test_mae:.2f}, RMSE = PKR {np.sqrt(test_mse):.2f}")

    # Ensure output directories exist
    os.makedirs("assets/ml", exist_ok=True)

    # Save normalization parameters for Flutter service
    norm_file = "assets/ml/pricing_normalization.json"
    with open(norm_file, "w") as f:
        json.dump(norm_params, f, indent=2)
    print(f"Saved normalization parameters to {norm_file}")

    # Convert and save as TensorFlow Lite (.tflite)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    # Optimize for size/latency
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    tflite_path = "assets/ml/pricing_model.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    print(f"Successfully converted and saved TFLite model to {tflite_path} ({len(tflite_model)} bytes)")

    # Test TFLite interpreter locally with sample prediction
    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    sample_input = x_test[:1]
    interpreter.set_tensor(input_details[0]['index'], sample_input)
    interpreter.invoke()
    tflite_prediction = interpreter.get_tensor(output_details[0]['index'])[0][0]
    actual_val = y_test[0]

    print(f"\nTFLite Local Verification:")
    print(f"Input features (raw): {test_df.iloc[0][features].to_dict()}")
    print(f"TFLite Predicted Sweet Spot: PKR {tflite_prediction:.1f}")
    print(f"Actual Accepted Bid in Data: PKR {actual_val:.1f}")

if __name__ == "__main__":
    train_and_export()
