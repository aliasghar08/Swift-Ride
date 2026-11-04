import numpy as np
import pandas as pd
import os

def generate_synthetic_ride_data(num_samples: int = 12000, seed: int = 42) -> pd.DataFrame:
    np.random.seed(seed)

    # Ride distances across Pakistani urban and peri-urban routes (1km to 40km)
    distances = np.clip(np.random.exponential(scale=7.0, size=num_samples) + 0.8, 1.0, 40.0)

    # Time of day (0.0 to 24.0 hours)
    time_of_day = np.random.uniform(0.0, 24.0, size=num_samples)

    # Rain probability (~12% monsoon/winter showers)
    is_raining = np.random.binomial(n=1, p=0.12, size=num_samples)

    # Vehicle / Car tier:
    # 0 = Bike / Moto
    # 1 = Auto Rikshaw
    # 2 = Car Economy Hatchback (Suzuki Alto, Cultus, WagonR, Mira)
    # 3 = Car Sedan / Comfort AC (Toyota Corolla, Yaris, Honda Civic, City)
    car_tier = np.random.choice([0, 1, 2, 3], size=num_samples, p=[0.25, 0.20, 0.35, 0.20])

    # Traffic multiplier (1.0 to 1.75) representing road congestion conditions
    base_traffic = np.random.uniform(1.0, 1.25, size=num_samples)
    rush_hour_boost = np.where(
        ((time_of_day >= 8.0) & (time_of_day <= 10.5)) | ((time_of_day >= 17.0) & (time_of_day <= 21.0)),
        np.random.uniform(0.15, 0.35, size=num_samples),
        0.0
    )
    rain_boost = is_raining * np.random.uniform(0.10, 0.25, size=num_samples)
    traffic_multiplier = np.clip(base_traffic + rush_hour_boost + rain_boost, 1.0, 1.75)

    # Real-world fuel averages based on vehicle model and traffic degradation
    # Bike: 35-45 km/L
    # Rikshaw: 18-24 km/L
    # Car Economy (Alto/Cultus): 12-16 km/L (drops in stop-and-go)
    # Car Sedan (Corolla/Civic): 8.5-11.5 km/L (drops in stop-and-go)
    base_mileage = np.where(
        car_tier == 0, np.random.uniform(35.0, 45.0, size=num_samples),
        np.where(
            car_tier == 1, np.random.uniform(18.0, 24.0, size=num_samples),
            np.where(
                car_tier == 2, np.random.uniform(12.5, 16.5, size=num_samples),
                np.random.uniform(8.5, 11.5, size=num_samples)
            )
        )
    )
    # Stop-and-go traffic penalty degrades mileage
    traffic_mileage_penalty = (traffic_multiplier - 1.0) * 0.25
    fuel_average_km_l = np.clip(base_mileage * (1.0 - traffic_mileage_penalty), 6.0, 48.0)

    # --- Ground Truth Pakistan Regional Market Calibrated Fare Structure ---
    # Current market rates in Punjab & Sindh (Lahore, Karachi, Faisalabad, Rawalpindi)
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

    # Fuel consumption factor: cars with heavier engines / lower km/L command a fare premium
    # Normalized against standard economy 13 km/L
    fuel_burden_multiplier = np.where(
        car_tier >= 2,
        np.clip((14.0 / fuel_average_km_l) ** 0.35, 0.90, 1.30),
        1.0
    )

    # Calculate raw fare with distance, congestion traffic multiplier, and vehicle fuel economics
    raw_fare = (base_fare + (distances * km_rate * fuel_burden_multiplier)) * traffic_multiplier

    # Human peer-to-peer bidding / negotiation variance (+/- 5%)
    haggling_noise = np.random.normal(loc=0.0, scale=0.04 * raw_fare, size=num_samples)
    min_floor = np.where(car_tier == 0, 70.0, np.where(car_tier == 1, 120.0, np.where(car_tier == 2, 210.0, 280.0)))
    final_accepted_bid = np.round(np.clip(raw_fare + haggling_noise, min_floor, None) / 5.0) * 5.0

    df = pd.DataFrame({
        "distance_km": np.round(distances, 2),
        "time_of_day_hours": np.round(time_of_day, 2),
        "is_raining": is_raining,
        "traffic_multiplier": np.round(traffic_multiplier, 3),
        "car_tier": car_tier,
        "fuel_average_km_l": np.round(fuel_average_km_l, 2),
        "final_accepted_bid": final_accepted_bid
    })

    return df

if __name__ == "__main__":
    df = generate_synthetic_ride_data(num_samples=12000)
    current_dir = os.path.dirname(__file__)
    output_path = os.path.join(current_dir, "ride_data.csv")
    df.to_csv(output_path, index=False)
    print(f"✅ Generated {len(df)} realistic market-calibrated ride records at {output_path}")
    print("\nSample records:")
    print(df.head(10))
    print("\nPrice statistics by Vehicle/Car Tier:")
    for tier, name in [(0, "Bike"), (1, "Rikshaw"), (2, "Car Economy (Alto/Cultus)"), (3, "Car Sedan (Corolla/Civic)")]:
        sub = df[df["car_tier"] == tier]
        print(f" - {name:28s}: mean distance={sub['distance_km'].mean():.1f}km, mean fare=PKR {sub['final_accepted_bid'].mean():.1f}, min=PKR {sub['final_accepted_bid'].min():.0f}, max=PKR {sub['final_accepted_bid'].max():.0f}")
