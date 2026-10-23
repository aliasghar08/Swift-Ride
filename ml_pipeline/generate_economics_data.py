import numpy as np
import pandas as pd
import os

np.random.seed(42)
n_samples = 10000

# Feature distributions for Punjab transit (Jhang / Toba / Faisalabad / Lahore)
distance_km = np.random.uniform(1.0, 35.0, n_samples)
vehicle_type = np.random.choice([0, 1, 2], n_samples, p=[0.35, 0.25, 0.40]) # 0=Bike, 1=Rikshaw, 2=Car
booked_seats = np.array([
    1 if v == 0 else (np.random.randint(1, 3) if v == 1 else np.random.randint(1, 5))
    for v in vehicle_type
])

# Congestion index: 1.0 (free highway) to 2.4 (heavy city bazaar gridlock)
congestion_ratio = np.random.uniform(1.0, 2.2, n_samples)
duration_min = (distance_km / np.where(vehicle_type == 0, 30.0, np.where(vehicle_type == 1, 22.0, 25.0))) * 60.0 * congestion_ratio
fuel_price = np.random.uniform(360.0, 395.0, n_samples)

# --- Ground Truth Target Formulations (Physics + Behavioral Economics) ---
# 1. Fuel L: Bike=30 km/L, Rikshaw=22 km/L, Car=10 km/L base
base_km_l = np.where(vehicle_type == 0, 30.0, np.where(vehicle_type == 1, 22.0, 10.0))
seat_penalty = 1.0 + (booked_seats - 1) * 0.04
congestion_fuel_penalty = 1.0 + (congestion_ratio - 1.0) * 0.35
fuel_liters = (distance_km / (base_km_l / (seat_penalty * congestion_fuel_penalty))) + np.random.normal(0, 0.02, n_samples)
fuel_liters = np.clip(fuel_liters, 0.05, 12.0)

# 2. Maintenance PKR: wear increases with stop-and-go friction
base_wear_per_km = np.where(vehicle_type == 0, 2.5, np.where(vehicle_type == 1, 2.5, 4.0))
maintenance_pkr = (distance_km * base_wear_per_km * (1.0 + (congestion_ratio - 1.0) * 0.5)) + np.random.normal(0, 2.0, n_samples)
maintenance_pkr = np.clip(maintenance_pkr, 2.0, 500.0)

# 3. Market Fare PKR: dynamic market clearing price
base_fare = np.where(vehicle_type == 0, 60.0, np.where(vehicle_type == 1, 100.0, 180.0))
km_rate = np.where(vehicle_type == 0, 20.0, np.where(vehicle_type == 1, 32.0, 48.0))
min_rate = np.where(vehicle_type == 0, 1.8, np.where(vehicle_type == 1, 3.0, 4.5))
fare_pkr = (base_fare + (distance_km * km_rate) + (duration_min * min_rate)) * np.where(booked_seats > 1, 1.0 + (booked_seats - 1) * 0.10, 1.0)
fare_pkr = np.round(fare_pkr / 5.0) * 5.0  # round to nearest 5 PKR

df = pd.DataFrame({
    'distance_km': np.round(distance_km, 2),
    'duration_min': np.round(duration_min, 1),
    'congestion_ratio': np.round(congestion_ratio, 2),
    'vehicle_type': vehicle_type,
    'booked_seats': booked_seats,
    'fuel_price': np.round(fuel_price, 2),
    'target_fuel_liters': np.round(fuel_liters, 3),
    'target_maintenance_pkr': np.round(maintenance_pkr, 1),
    'target_fare_pkr': fare_pkr,
})

out_dir = os.path.dirname(__file__)
out_path = os.path.join(out_dir, 'economics_data.csv')
df.to_csv(out_path, index=False)
print(f"✅ Generated {len(df)} synthetic multi-target ride records at {out_path}.")
