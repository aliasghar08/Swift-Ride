import numpy as np
import pandas as pd
import os

np.random.seed(42)
n_samples = 25000

# 1. Distance (1.0 to 45.0 km across Punjab urban & regional transit)
distance_km = np.random.uniform(1.0, 45.0, n_samples)

# 2. Vehicle Tier:
# 0 = Bike (70-125cc)
# 1 = Auto Rikshaw
# 2 = Car 660cc (Alto / Mira)
# 3 = Car 1000cc (WagonR / Cultus)
# 4 = Sedan 1300cc+ (Corolla / Yaris / City)
vehicle_tier = np.random.choice([0, 1, 2, 3, 4], n_samples, p=[0.22, 0.18, 0.25, 0.20, 0.15])

# 3. Congestion Ratio (1.0 free-flow bypass to 2.4 heavy bazaar gridlock)
congestion_ratio = np.random.uniform(1.0, 2.4, n_samples)

# 4. Cruising Speeds (km/h) in free-flow conditions
free_flow_speed = np.where(
    vehicle_tier == 0, 35.0, # Bike
    np.where(
        vehicle_tier == 1, 26.0, # Auto Rikshaw
        np.where(
            vehicle_tier == 2, 40.0, # 660cc
            np.where(vehicle_tier == 3, 42.0, 46.0) # 1000cc, Sedan
        )
    )
)
duration_min = (distance_km / free_flow_speed) * 60.0 * congestion_ratio

# 5. Road Surface Condition:
# 0 = Smooth Paved Highway, 1 = Normal Urban / Patchy, 2 = Broken / Rough Rural
road_condition = np.random.choice([0, 1, 2], n_samples, p=[0.35, 0.45, 0.20])

# 6. Booked Seats (Passengers payload)
booked_seats = np.array([
    1 if t == 0 else (np.random.randint(1, 3) if t == 1 else np.random.randint(1, 5))
    for t in vehicle_tier
])

# 7. Air Conditioning Load (0 = Off, 1 = On)
# Bike and Rikshaw cannot run AC; Cars have high AC adoption (75%)
ac_enabled = np.array([
    0 if t in (0, 1) else (1 if np.random.rand() < 0.75 else 0)
    for t in vehicle_tier
])

# 8. OGRA Petrol Prices in Pakistan (PKR 270 to 400/L)
fuel_price = np.random.uniform(270.0, 400.0, n_samples)

# --- Ground Truth Non-Linear Physics Calculations ---

# Baseline uninhibited fuel mileage (km/L)
base_fuel_average_km_l = np.where(
    vehicle_tier == 0, np.random.uniform(40.0, 48.0, n_samples), # Bike (~44 km/L)
    np.where(
        vehicle_tier == 1, np.random.uniform(21.0, 25.0, n_samples), # Rikshaw (~23 km/L)
        np.where(
            vehicle_tier == 2, np.random.uniform(18.0, 21.0, n_samples), # 660cc (~19.5 km/L)
            np.where(
                vehicle_tier == 3, np.random.uniform(14.5, 17.5, n_samples), # 1000cc (~16.0 km/L)
                np.random.uniform(11.5, 14.5, n_samples) # Sedan 1300cc+ (~13.0 km/L)
            )
        )
    )
)

# A. Congestion Penalty (idling in 1st/2nd gear degrades mileage by up to ~32%)
congestion_fuel_penalty = 1.0 + (congestion_ratio - 1.0) * 0.23

# B. Road Condition Penalty (rough roads require lower gears / higher RPM: 0%, 7.5%, 19%)
road_fuel_penalty = np.where(road_condition == 0, 1.0, np.where(road_condition == 1, 1.075, 1.19))

# C. AC Compressor Drag Penalty (stronger parasitic draw on 660cc engines)
ac_fuel_penalty = np.where(
    ac_enabled == 1,
    np.where(vehicle_tier == 2, 1.176, np.where(vehicle_tier == 3, 1.149, 1.136)),
    1.0
)

# D. Passenger Payload Penalty (~3.5% per extra seat beyond driver/solo)
seat_fuel_penalty = 1.0 + (booked_seats - 1) * 0.035

effective_km_l = base_fuel_average_km_l / (
    congestion_fuel_penalty * road_fuel_penalty * ac_fuel_penalty * seat_fuel_penalty
)

fuel_liters = (distance_km / effective_km_l) + np.random.normal(0, 0.015, n_samples)
fuel_liters = np.clip(fuel_liters, 0.03, 15.0)

# Mechanical Wear & Maintenance (PKR):
# Base wear rates: Bike 1.5, Rikshaw 2.5, Car 660cc 3.2, Car 1000cc 4.0, Sedan 5.2 PKR/km
base_wear_per_km = np.where(
    vehicle_tier == 0, 1.50,
    np.where(
        vehicle_tier == 1, 2.50,
        np.where(
            vehicle_tier == 2, 3.20,
            np.where(vehicle_tier == 3, 4.00, 5.20)
        )
    )
)

# Wear scales with road roughness (+0%, +20%, +45%) and stop-and-go congestion
road_wear_mult = np.where(road_condition == 0, 1.0, np.where(road_condition == 1, 1.20, 1.45))
congestion_wear_mult = 1.0 + (congestion_ratio - 1.0) * 0.35
maintenance_pkr = (distance_km * base_wear_per_km * road_wear_mult * congestion_wear_mult) + np.random.normal(0, 1.0, n_samples)
maintenance_pkr = np.clip(maintenance_pkr, 2.0, 950.0)

# Target Pakistan Regional Market Sweet-Spot Fare (PKR):
base_fare = np.where(
    vehicle_tier == 0, 70.0,
    np.where(
        vehicle_tier == 1, 120.0,
        np.where(
            vehicle_tier == 2, 180.0,
            np.where(vehicle_tier == 3, 210.0, 250.0)
        )
    )
)

km_rate = np.where(
    vehicle_tier == 0, 22.0,
    np.where(
        vehicle_tier == 1, 34.0,
        np.where(
            vehicle_tier == 2, 46.0,
            np.where(vehicle_tier == 3, 52.0, 60.0)
        )
    )
)

min_rate = np.where(
    vehicle_tier == 0, 2.0,
    np.where(
        vehicle_tier == 1, 3.0,
        np.where(
            vehicle_tier == 2, 4.5,
            np.where(vehicle_tier == 3, 5.5, 7.0)
        )
    )
)

ac_surcharge = np.where(ac_enabled == 1, 1.08, 1.0)
seat_boost = np.where(booked_seats > 1, 1.0 + (booked_seats - 1) * 0.05, 1.0)
raw_fare = ((base_fare + (distance_km * km_rate) + (duration_min * min_rate)) * ac_surcharge) * seat_boost

# Protect driver net take-home margin: fare must cover direct expenses + minimum 35% margin
fuel_cost = fuel_liters * fuel_price
direct_expenses = fuel_cost + maintenance_pkr
safe_fare = np.maximum(raw_fare, direct_expenses * 1.35)
fare_pkr = np.round(safe_fare / 5.0) * 5.0

df = pd.DataFrame({
    'distance_km': np.round(distance_km, 2),
    'duration_min': np.round(duration_min, 1),
    'congestion_ratio': np.round(congestion_ratio, 2),
    'vehicle_tier': vehicle_tier,
    'road_condition': road_condition,
    'ac_enabled': ac_enabled,
    'booked_seats': booked_seats,
    'fuel_price': np.round(fuel_price, 2),
    'target_fuel_liters': np.round(fuel_liters, 3),
    'target_maintenance_pkr': np.round(maintenance_pkr, 1),
    'target_fare_pkr': fare_pkr,
})

out_dir = os.path.dirname(__file__)
out_path = os.path.join(out_dir, 'economics_data.csv')
df.to_csv(out_path, index=False)
print(f"✅ Generated {len(df)} multi-target trip records calibrated for Pakistan regional fleet at {out_path}.")
print("\nSample records:")
print(df.head(6))
