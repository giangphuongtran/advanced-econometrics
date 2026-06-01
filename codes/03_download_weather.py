import cdsapi
import os
import time

c = cdsapi.Client()

# Define parameters
year_to_download = ['2020', '2021', '2022', '2023', '2024']
# EU bounding box [North, West, South, East]
bounding_box = [70, -10, 35, 30]
output_folder = "era5_eu_data"

os.makedirs(output_folder, exist_ok=True)

months = [f"{str(i).zfill(2)}" for i in range(1, 13)]

def download_era5_data(year, month):
	# FIXED: Changed 'poland' to 'eu'
	file_name = f"{output_folder}/era5_eu_{year}_{month}.nc"

	if os.path.exists(file_name):
		print(f"File {file_name} already exists, skipping...")
		return

	print(f"Requesting data for {year}-{month}... (This may take a while to process on CDS servers)")

	try:
		c.retrieve(
			'reanalysis-era5-single-levels',
			{
				'product_type': 'reanalysis',
				'data_format': 'netcdf',
				'variable': [
					'2m_temperature',
					'2m_dewpoint_temperature',
					'surface_solar_radiation_downwards',
					'total_precipitation',
					'10m_u_component_of_wind',
					'10m_v_component_of_wind',
					'total_cloud_cover'
				],
				'year': year,
				'month': month,
				'day': [
					'01', '02', '03', '04', '05', '06', '07', '08', '09', '10',
					'11', '12', '13', '14', '15', '16', '17', '18', '19', '20',
					'21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31',
				],
				'time': [
					'00:00', '01:00', '02:00', '03:00', '04:00', '05:00',
					'06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
					'12:00', '13:00', '14:00', '15:00', '16:00', '17:00',
					'18:00', '19:00', '20:00', '21:00', '22:00', '23:00',
				],
				'area': bounding_box,
			},
			file_name
		)
		print(f"Successfully downloaded {file_name}")
	except Exception as e:
		print(f"Failed to download {year}-{month}. Error: {e}")

if __name__ == "__main__":
	for year in year_to_download:
		for month in months:
			download_era5_data(year, month)
			# 60 seconds is a good buffer, but the CDS API usually handles queuing gracefully anyway
			time.sleep(60)

	# FIXED: Moved inside the execution block
	print("All downloads complete!")