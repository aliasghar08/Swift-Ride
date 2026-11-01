import numpy as np
import pandas as pd
import os

np.random.seed(42)
n_samples = 15000

# Feature distributions calibrated for Pakistan urban & suburban routes
distance_km = np.random.uniform(1.0, 38.0, n_samples)
car_tier = np.random.choice([0, 1, 2, 3], n_samples, p=[0.25, 0.20, 0.35, 0.20])
# vehicle_type for backward compatibility: 0=Bike, 1=Rikshaw, 2=Car
vehicle_type = np.where(car_tier == 0, 0, np.where(car_tier == 1, 1, 2))

booked_seats = np.array([
    1 if t == 0 else (np.random.randint(1, 3) if t == 1 else np.random.randint(1, 5))
    for t in car_tier
])

# Road congestion ratio: 1.0 (free highway) to 2.4 (dense urban gridlock)
congestion_ratio = np.random.uniform(1.0, 2.3, n_samples)

# Cruising speeds (km/h) by vehicle type in free flow
free_flow_speed = np.where(car_tier == 0, 32.0, np.where(car_tier == 1, 24.0, 38.0))
duration_min = (distance_km / free_flow_speed) * 60.0 * congestion_ratio

# OGRA Petrol prices in Pakistan (PKR 320 to 395/L)
fuel_price = np.random.uniform(340.0, 395.0, n_samples)

# Baseline vehicle mileage (km/L) without congestion penalty
base_fuel_average_km_l = np.where(
    car_tier == 0, np.random.uniform(36.0, 44.0, n_samples), # Bike (CD70, CG125)
    np.where(
        car_tier == 1, np.random.uniform(18.0, 23.0, n_samples), # 4-stroke Auto Rikshaw
        np.where(
            car_tier == 2, np.random.uniform(13.0, 16.5, n_samples), # Alto, Cultus, WagonR
            np.random.uniform(8.5, 11.5, n_samples) # Corolla, Civic, Yaris
        )
    )
)

# --- Ground Truth Target Formulations (Automotive Physics + Market Reality) ---
# 1. Target Fuel Burn (Liters):
# Increased passenger load and stop-and-go congestion degrade fuel economy
seat_penalty = 1.0 + (booked_seats - 1) * 0.045
congestion_fuel_penalty = 1.0 + (congestion_ratio - 1.0) * 0.40
effective_km_l = base_fuel_average_km_l / (seat_penalty * congestion_fuel_penalty)
fuel_liters = (distance_km / effective_km_l) + np.random.normal(0, 0.02, n_samples)
fuel_liters = np.clip(fuel_liters, 0.05, 15.0)

# 2. Target Mechanical Maintenance & Wear (PKR):
# Wear accelerates in dense stop-and-go urban traffic (brakes, clutch, engine heat)
base_wear_per_km = np.where(
    car_tier == 0, 1.5,
    np.where(
        car_tier == 1, 2.5,
        np.where(car_tier == 2, 3.5, 5.5)
    )
)
maintenance_pkr = (distance_km * base_wear_per_km * (1.0 + (congestion_ratio - 1.0) * 0.55)) + np.random.normal(0, 1.5, n_samples)
maintenance_pkr = np.clip(maintenance_pkr, 2.0, 800.0)

# 3. Target inDrive Pakistan Market Clearing Fare (PKR):
base_fare = np.where(
    car_tier == 0, 75.0,
    np.where(
        car_tier == 1, 130.0,
        np.where(car_tier == 2, 210.0, 280.0)
    )
)
km_rate = np.where(
    car_tier == 0, 28.0,
    np.where(
        car_tier == 1, 45.0,
        np.where(car_tier == 2, 62.0, 82.0)
    )
)
min_rate = np.where(
    car_tier == 0, 2.5,
    np.where(
        car_tier == 1, 4.0,
        np.where(car_tier == 2, 6.0, 8.0)
    )
)

seat_fare_boost = np.where(booked_seats > 1, 1.0 + (booked_seats - 1) * 0.08, 1.0)
raw_fare = (base_fare + (distance_km * km_rate) + (duration_min * min_rate)) * seat_fare_boost
# Ensure fare covers at least (fuel_cost + maintenance + 30% driver wage)
fuel_cost_est = fuel_liters * fuel_price
cost_floor = (fuel_cost_est + maintenance_pkr) * 1.35
safe_fare = np.maximum(raw_fare, cost_floor)
fare_pkr = np.round(safe_fare / 5.0) * 5.0  # round to nearest 5 PKR

df = pd.DataFrame({
    'distance_km': np.round(distance_km, 2),
    'duration_min': np.round(duration_min, 1),
    'congestion_ratio': np.round(congestion_ratio, 2),
    'vehicle_type': vehicle_type,
    'car_tier': car_tier,
    'fuel_average_km_l': np.round(base_fuel_average_km_l, 2),
    'booked_seats': booked_seats,
    'fuel_price': np.round(fuel_price, 2),
    'target_fuel_liters': np.round(fuel_liters, 3),
    'target_maintenance_pkr': np.round(maintenance_pkr, 1),
    'target_fare_pkr': fare_pkr,
})

out_dir = os.path.dirname(__file__)
out_path = os.path.join(out_dir, 'economics_data.csv')
df.to_csv(out_path, index=False)
print(f"✅ Generated {len(df)} multi-target ride records calibrated for inDrive Pakistan at {out_path}.")
print("\nSample records:")
print(df.head(6))
