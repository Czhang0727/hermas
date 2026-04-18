#!/usr/bin/env python3
"""
Weather Report Script
Fetches tomorrow's weather for 5 Chinese cities using curl and generates a table.
Uses Open-Meteo API (free, no API key required)
"""

import subprocess
import json
import re
from datetime import datetime, timedelta

# City data: name, latitude, longitude
CITIES = {
    "北京": (39.9042, 116.4074),
    "上海": (31.2304, 121.4737),
    "广州": (23.1291, 113.2644),
    "深圳": (22.5431, 114.0579),
    "杭州": (30.2741, 120.1551),
}

def get_weather_lat_lon(lat, lon):
    """Fetch weather data for given coordinates using curl and Open-Meteo API"""
    # Get current date and calculate tomorrow's date
    tomorrow = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
    
    # Open-Meteo API URL
    url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&daily=temperature_2m_max,temperature_2m_min,weathercode,precipitation_probability_max&timezone=Asia%2FShanghai&forecast_days=7"
    
    # Use curl to fetch the data
    result = subprocess.run(
        ["curl", "-s", url],
        capture_output=True,
        text=True,
        timeout=30
    )
    
    if result.returncode != 0:
        return None
    
    try:
        data = json.loads(result.stdout)
        
        # Extract tomorrow's weather (index 1 since index 0 is today)
        daily = data.get("daily", {})
        dates = daily.get("time", [])
        
        if len(dates) < 2:
            return None
        
        tomorrow_idx = 1  # Index for tomorrow
        temp_max = daily.get("temperature_2m_max", [None])[tomorrow_idx]
        temp_min = daily.get("temperature_2m_min", [None])[tomorrow_idx]
        weather_code = daily.get("weathercode", [None])[tomorrow_idx]
        precip_prob = daily.get("precipitation_probability_max", [None])[tomorrow_idx]
        
        # Decode WMO weather code
        weather_desc = decode_weather_code(weather_code)
        
        return {
            "temp_max": temp_max,
            "temp_min": temp_min,
            "weather": weather_desc,
            "precipitation": precip_prob
        }
    except (json.JSONDecodeError, IndexError, KeyError):
        return None

def decode_weather_code(code):
    """Decode WMO weather code to description"""
    codes = {
        0: "晴朗",
        1: "多云",
        2: "阴天",
        3: "小雨",
        45: "雾",
        48: "毛毛雨",
        51: "小雨",
        53: "中雨",
        55: "大雨",
        61: "小雨",
        63: "中雨",
        65: "大雨",
        71: "小雪",
        73: "中雪",
        75: "大雪",
        80: "阵雨",
        81: "中阵雨",
        82: "大阵雨",
        95: "雷雨",
        96: "雷阵雨伴冰雹",
        99: "强雷雨伴冰雹"
    }
    return codes.get(code, "未知")

def generate_table(cities_data):
    """Generate a formatted table of weather data"""
    # Header
    header = f"{'城市':<8} {'明天天气':<8} {'最高温':<8} {'最低温':<8} {'降水概率':<8}"
    separator = "-" * len(header)
    
    rows = [header, separator]
    
    for city, data in cities_data.items():
        if data:
            row = f"{city:<8} {data['weather']:<8} {data['temp_max']:<8} {data['temp_min']:<8} {data['precipitation']:<8}%"
        else:
            row = f"{city:<8} {'获取失败':<8} {'-':<8} {'-':<8} {'-':<8}"
        rows.append(row)
    
    return "\n".join(rows)

def main():
    print("正在获取 5 个城市的明天天气数据...\n")
    
    cities_data = {}
    
    for city, (lat, lon) in CITIES.items():
        print(f"正在获取 {city} 的天气数据...")
        weather = get_weather_lat_lon(lat, lon)
        cities_data[city] = weather
        if weather:
            print(f"  ✓ {city}: {weather['weather']}, {weather['temp_min']}°C - {weather['temp_max']}°C")
        else:
            print(f"  ✗ {city}: 获取失败")
    
    print("\n")
    
    # Generate and display the table
    table = generate_table(cities_data)
    print(table)
    
    # Save to file
    with open("weather_report.txt", "w", encoding="utf-8") as f:
        f.write("========== 中国五大城市天气预报（明天）==========\n")
        f.write(f"生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(table)
        f.write("\n\n数据来源：Open-Meteo API (https://open-meteo.com/)\n")
    
    print(f"\n✓ 报告已保存为 weather_report.txt")

if __name__ == "__main__":
    main()
