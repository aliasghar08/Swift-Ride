import numpy as np
import pandas as pd

def generate_synthetic_ride_data(num_samples: int = 5000, seed: int = 42) -> pd.DataFrame:
    np.random.seed(seed)

    # Simulated ride distances in Jhang & Toba Tek Singh (intercity/intracity: 1km to 35km)
    # Exponential distribution favoring shorter rides (2-8km) but including longer intercity hops
    distances = np.clip(np.random.exponential(scale=6.5, size=num_samples) + 0.8, 1.0, 38.0)

    # Time of day (0.0 to 24.0 hours) with peaks around morning commute (8-10am) and evening (5-9pm)
    time_of_day = np.random.uniform(0.0, 24.0, size=num_samples)

    # Rain probability (monsoon/winter rain simulation, ~12% probability)
    is_raining = np.random.binomial(n=1, p=0.12, size=num_samples)

    # Traffic multiplier (1.0 to 1.5) influenced by rush hours and rain
    base_traffic = np.random.uniform(1.0, 1.25, size=num_samples)
    rush_hour_boost = np.where(
        ((time_of_day >= 8.0) & (time_of_day <= 10.5)) | ((time_of_day >= 17.0) & (time_of_day <= 20.5)),
        np.random.uniform(0.1, 0.25, size=num_samples),
        0.0
    )
    rain_boost = is_raining * np.random.uniform(0.05, 0.15, size=num_samples)
    traffic_multiplier = np.clip(base_traffic + rush_hour_boost + rain_boost, 1.0, 1.5)

    # Formula: (Base PKR 50 + (distance_km * PKR 25)) * traffic_multiplier
    # Plus human haggling variance (+/- 5% to 10%)
    base_calc = (50.0 + (distances * 25.0)) * traffic_multiplier
    haggling_noise = np.random.normal(loc=0.0, scale=0.06 * base_calc, size=num_samples)
    final_accepted_bid = np.round(np.clip(base_calc + haggling_noise, 50.0, None), 1)

    df = pd.DataFrame({
        "distance_km": np.round(distances, 2),
        "time_of_day_hours": np.round(time_of_day, 2),
        "is_raining": is_raining,
        "traffic_multiplier": np.round(traffic_multiplier, 3),
        "final_accepted_bid": final_accepted_bid
    })

    return df

if __name__ == "__main__":
    df = generate_synthetic_ride_data(num_samples=5000)
    output_path = "ml_pipeline/ride_data.csv"
    df.to_csv(output_path, index=False)
    print(f"Successfully generated {len(df)} rows and saved to {output_path}")
    print(df.head(10))
    print("\nSummary Statistics:")
    print(df.describe())
