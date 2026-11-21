import requests
from flask import Flask, request, jsonify, redirect
from dotenv import load_dotenv
import google.generativeai as genai 
import os
import json
from novu.api import EventApi
from novu.dto.subscriber import SubscriberDto
from novu.api.subscriber import SubscriberApi
from novu.dto.event import InputEventDto

from firebase_admin import credentials, initialize_app, firestore
load_dotenv()

db = None
firebase_env = os.getenv('firebase')
if firebase_env:
    try:
        cred = credentials.Certificate(json.loads(firebase_env))
        firebase_app = initialize_app(cred)
        db = firestore.client()
        print("Firebase initialized successfully from environment variable.")
    except Exception as e:
        print(f"Error initializing Firebase from env: {e}")
elif os.path.exists(os.path.join(os.path.dirname(__file__), 'firebase.json')):
    try:
        cred = credentials.Certificate(os.path.join(os.path.dirname(__file__), 'firebase.json'))
        firebase_app = initialize_app(cred)
        db = firestore.client()
        print("Firebase initialized successfully from firebase.json.")
    except Exception as e:
        print(f"Error initializing Firebase from firebase.json: {e}")
else:
    print("Notice: No Firebase credentials provided. Running in offline/mock fallback mode.")

local_store = {"needs_and_gives": {"need": [], "give": []}}


WEATHER_API=os.getenv('WEATHERAPI_API_KEY')
GEMINI_API=os.getenv('GEMINI_API_KEY')
GROQ_API_KEY=os.getenv('GROQ_API_KEY')
GROQ_MODEL=os.getenv('GROQ_MODEL', 'qwen/qwen3.8-27b')
NOVU_KEY=os.getenv('NOVUS_API_KEY')

app = Flask(__name__)



@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,PUT,POST,DELETE,OPTIONS'
    return response

@app.route('/', methods=['GET'])
def index():
    return '<samp>🔼 Sahaya Flask for Backend?</samp>'


@app.route('/api/gemini/',methods = ['GET'])
def gemini():
    city = request.args.get('city', 'Chennai')

    prompt = f"""You are Sahaya, an AI disaster relief assistant. Analyze the weather situation for {city}.
Respond with a strict JSON object:
{{
  "Color": "Red" or "Orange" or "Yellow" or "White",
  "weather": "one-word weather condition (e.g. Thunderstorm, Rainy, Cloudy, Sunny, Cyclone)",
  "time": "estimated time to calamity in hours e.g. 3",
  "Alert": "A concise 1-2 line warning for {city}",
  "Precautions": [
    "first precaution for residents",
    "second precaution",
    "third precaution"
  ]
}}"""

    if GROQ_API_KEY:
        try:
            res = requests.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": "You are a disaster relief AI. Respond strictly in valid JSON."},
                        {"role": "user", "content": prompt}
                    ],
                    "response_format": {"type": "json_object"}
                },
                timeout=15
            )
            if res.status_code == 200:
                data = res.json()
                content = data['choices'][0]['message']['content']
                return jsonify(json.loads(content))
        except Exception as e:
            print(f"Error with Groq Qwen model: {e}")

    if not WEATHER_API or not GEMINI_API:
        weather_path = os.path.join(os.path.dirname(__file__), '..', 'mobile', 'assets', 'weatherData.json')
        if os.path.exists(weather_path):
            with open(weather_path, 'r') as f:
                return jsonify(json.load(f))
        return jsonify({
            "Color": "red",
            "weather": "Thunderstorm",
            "Alert": f"Severe Weather Alert for {city}",
            "time": "4",
            "Precautions": [
                "Water logging expected in low-lying areas. Avoid travel.",
                "Ensure emergency power backups and drinking water supplies.",
                "Keep emergency numbers and first aid handy."
            ]
        })

    try:
        URL = f"http://api.weatherapi.com/v1/forecast.json?key={WEATHER_API}&q={city}&days=2&aqi=yes&alerts=yes"
        weather_pattern = requests.get(URL).json()
        genai.configure(api_key=GEMINI_API)
        model = genai.GenerativeModel('gemini-pro')

        prompt = f"""This is the current weather at {city}: {weather_pattern}. Analyze this data to generate a warning if there's a forecast of any severe weather events like Thunderstorms, Hurricanes, Tornadoes, Tsunamis, Hailstorms, Cyclones, or Heatwaves within the next 48 hours. The warning should include the type of event, its anticipated time of occurrence, and precautionary measures specific to {city}.
        Please format the response according to the following JSON schema:
        'Color': 'Specify the color based on the severity of the weather event. Use Red for high severity, Orange for moderate severity, Yellow for mild severity, and White if there are no severe events.',
        'weather': 'Current weather condition in one word (e.g., sunny, cloudy, rainy, thunderstorm, snow, clear).',
        'time': 'Estimated time of arrival (ETA) in hours for the severe weather event.',
        'Alert': 'A concise 1-2 line warning about the predicted weather event, including the nearest first occurrence.',
        'Precautions': 'A list of precautionary measures tailored to the specific weather event and the city in question. Each measure should be a string element in the list.'"""

        response = model.generate_content(prompt)
        dic = json.loads(response.text)
        return jsonify(dic)
    except Exception as e:
        print(f"Error in gemini endpoint: {e}")
        return jsonify({
            "Color": "orange",
            "weather": "Rainy",
            "Alert": f"Weather advisory for {city}: Moderate showers expected.",
            "time": "2",
            "Precautions": ["Carry an umbrella", "Drive cautiously"]
        })


def add_data_to_firestore(collection_name, key, data):
    if db:
        doc_ref = db.collection(collection_name).document(key)
        current_data = doc_ref.get().to_dict()
        if current_data and key in current_data:
            if isinstance(current_data[key], list):
                current_data[key].append(data)
            else:
                current_data[key] = [current_data[key], data]
        else:
            current_data = {key: [data]}
        doc_ref.set(current_data)
    else:
        if collection_name not in local_store:
            local_store[collection_name] = {}
        if key not in local_store[collection_name]:
            local_store[collection_name][key] = []
        local_store[collection_name][key].append(data)


@app.route('/api/post/',methods = ['POST'])
def add_details():
    try:
        data = request.get_json()
        if not data or 'mode' not in data:
            raise ValueError("Missing 'mode' key in the request.")

        key = data['mode']
        data_copy = dict(data)
        data_copy.pop('mode')
        add_data_to_firestore('needs_and_gives', key, data_copy)
        return jsonify({'message': 'success'}), 200
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500



@app.route('/api/v1/', methods=['GET'])
def get_data_from_firestore():
    if db:
        try:
            doc_ref = db.collection('needs_and_gives')
            docs = doc_ref.stream()
            data_dict = {}
            for doc in docs:
                data_dict.update(doc.to_dict())
            result = {"need": data_dict.get("need", []), "give": data_dict.get("give", [])}
            return jsonify(result)
        except Exception as e:
            print(f"Error fetching from firestore: {e}")

    # Fallback to backend.schema.json + local_store
    schema_path = os.path.join(os.path.dirname(__file__), '..', 'mobile', 'assets', 'backend.schema.json')
    base_needs, base_gives = [], []
    if os.path.exists(schema_path):
        try:
            with open(schema_path, 'r') as f:
                schema_data = json.load(f)
                base_needs = schema_data.get("need", [])
                base_gives = schema_data.get("give", [])
        except Exception as e:
            print(f"Error loading schema fallback: {e}")

    merged_needs = base_needs + local_store.get("needs_and_gives", {}).get("need", [])
    merged_gives = base_gives + local_store.get("needs_and_gives", {}).get("give", [])
    return jsonify({"need": merged_needs, "give": merged_gives})





def add_sub(sub_id,phone):

    if (SubscriberApi("https://api.novu.co", NOVU_KEY).get(sub_id)):
        return 0
    else:
        subscriber = SubscriberDto(
            email="",
            subscriber_id=sub_id, #This is what the subscriber_id looks like
            first_name="", 
            last_name="",  
            phone=phone,  
            avatar="",  
            )
        novu = SubscriberApi("https://api.novu.co", NOVU_KEY).create(subscriber)
        return 1
@app.route('/api/v1/sendtxt', methods=['POST'])
def send_message():
    sub = request.form.get('sub')
    event_api = EventApi("https://api.novu.co", NOVU_KEY)
    add_sub(sub['id'],sub['phone'])
    try:
        event_api.trigger(
            name="sahaya", # sends emergency message to particulat subscriber 
            recipients=sub,
            payload={}
        )
        return "Message sent successfully", 200
    except Exception as e:
        return f"Error sending message: {e}", 500
    
@app.route('/api/v1/sos', methods=['POST'])
def sos():
    try:
        sos = request.form.get()
        event=[]
        for i in sos:
            add_sub(i['id'],i['phone']) #to ensure he's a sub 
            event_1 = InputEventDto(
                name="digest-workflow-example", 
                recipients=i['id'],
                payload={},  
            )
            event.append(event_1)
        
        
        novu = EventApi("https://api.novu.co", NOVU_KEY).trigger_bulk(events=event)
        return "SOS", 200
    except Exception as e:
        return f"Error sending message: {e}", 500


if __name__ == '__main__':
    app.run(host="0.0.0.0", port=8080, debug=True)
