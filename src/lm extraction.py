import requests
import hashlib
import hmac
import base64
import time
import json

# LogicMonitor API credentials
access_id = ''  
access_key = '' 
company = ''  

# API endpoint details
http_verb = 'GET'
resource_path = '/device/devices'
base_url = f'https://{company}.logicmonitor.com/santaba/rest'

# Current timestamp in epoch milliseconds
timestamp = str(int(time.time() * 1000))
data = ''  # Data is empty for a GET request

# Concatenate request details
string_to_sign = http_verb + timestamp + data + resource_path

# Calculate the HMAC-SHA256 signature
signature = hmac.new(bytes(access_key , 'utf-8'), msg=bytes(string_to_sign, 'utf-8'), digestmod=hashlib.sha256).digest()

# Base64 encode the signature
encoded_signature = base64.b64encode(signature).decode('utf-8')

# Construct the authorization header
auth_header = f"LMv1 {access_id}:{encoded_signature}:{timestamp}"

# Prepare the headers for the HTTP request
headers = {
    'Authorization': auth_header,
    'Content-Type': 'application/json'
}

# Make the HTTP request
response = requests.get(f"{base_url}{resource_path}", headers=headers)

if response.status_code == 200:
    # Request was successful, parse and print the device list
    devices = response.json()
    print(json.dumps(devices, indent=4))
else:
    # There was a problem with the request
    print(f"Failed to fetch device list. Status Code: {response.status_code}")
    print("Response:", response.text)
