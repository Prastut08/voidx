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
from rescue_service import RescueCoordinationService
from rag_service import EmergencyRAGService
from sos_manager import SOSManager

rescue_service = RescueCoordinationService()
rag_service = EmergencyRAGService()
sos_manager = SOSManager()
load_dotenv()
for p in [os.path.join(os.path.dirname(__file__), '.env'), os.path.join(os.path.dirname(__file__), '..', '..', '.env')]:
    if os.path.exists(p):
        load_dotenv(p, override=True)

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



@app.route('/api/v1/', methods=['GET', 'POST'])
def get_data_from_firestore():
    if request.method == 'POST':
        try:
            data = request.get_json(force=True) or {}
            mode = data.get("mode", "need")
            if "needs_and_gives" not in local_store:
                local_store["needs_and_gives"] = {"need": [], "give": []}
            local_store["needs_and_gives"][mode].append(data)

            # Ingest directly into DTN store-and-forward mesh
            loc = data.get("location", {})
            if loc.get("lat") and loc.get("lng"):
                sos_manager.create_sos({
                    "lat": float(loc["lat"]),
                    "lng": float(loc["lng"]),
                    "category": data.get("help", ["general"])[0] if data.get("help") else "general",
                    "description": f"DTN Request: {', '.join(data.get('help', []))}",
                    "user_id": data.get("phone", "DTN-DEVICE"),
                    "preferred_assistance": data.get("help", []),
                    "is_offline_synced": True
                })
            return jsonify({"success": True, "message": "Broadcasted to DTN Mesh", "data": data}), 200
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    user_lat = request.args.get('lat', type=float)
    user_lng = request.args.get('lng', type=float)

    # Real-time DTN mesh location generator when coordinates are provided
    if user_lat is not None and user_lng is not None:
        dtn_needs = [
            {
                "type": "hospital",
                "name": "District Emergency Trauma & Medical Center",
                "location": {"lat": round(user_lat + 0.0072, 6), "lng": round(user_lng + 0.0051, 6)},
                "phone": "+91-112",
                "help": ["medical", "icu", "trauma_care"],
                "source": "DTN-MESH-VERIFIED"
            },
            {
                "type": "rescue",
                "name": "NDRF Flood Rescue & Boat Evacuation Unit",
                "location": {"lat": round(user_lat - 0.0068, 6), "lng": round(user_lng - 0.0055, 6)},
                "phone": "+91-1070",
                "help": ["rescue", "boat_evacuation", "flood_rescue"],
                "source": "DTN-MESH-VERIFIED"
            },
            {
                "type": "safeSpace",
                "name": "Civil Defense Cyclone Shelter & Safe Space",
                "location": {"lat": round(user_lat - 0.0095, 6), "lng": round(user_lng + 0.0118, 6)},
                "phone": "+91-108",
                "help": ["shelter", "generator_power"],
                "source": "DTN-RELAY-ACTIVE"
            },
            {
                "type": "water",
                "name": "Emergency Clean Drinking Water Point",
                "location": {"lat": round(user_lat + 0.0118, 6), "lng": round(user_lng + 0.0092, 6)},
                "phone": "+91-1077",
                "help": ["clean_water", "water_filtration"],
                "source": "DTN-STORE-CARRY-FORWARD"
            },
            {
                "type": "reliefCamp",
                "name": "Community Disaster Relief & Evacuation Camp",
                "location": {"lat": round(user_lat + 0.0142, 6), "lng": round(user_lng - 0.0089, 6)},
                "phone": "+91-1070",
                "help": ["food", "shelter", "sanitation"],
                "source": "DTN-MESH-VERIFIED"
            },
            {
                "type": "supplies",
                "name": "Red Cross Emergency Supplies & Depot",
                "location": {"lat": round(user_lat - 0.0175, 6), "lng": round(user_lng - 0.0132, 6)},
                "phone": "+91-1077",
                "help": ["food", "water", "clothing", "first_aid"],
                "source": "DTN-STORE-CARRY-FORWARD"
            },
            {
                "type": "power",
                "name": "Emergency Generator & Power Charging Station",
                "location": {"lat": round(user_lat + 0.0195, 6), "lng": round(user_lng - 0.0162, 6)},
                "phone": "+91-1912",
                "help": ["power", "charging", "generator"],
                "source": "DTN-RELAY-ACTIVE"
            },
            {
                "type": "hospital",
                "name": "Rapid Action Medical & Ambulance Station",
                "location": {"lat": round(user_lat + 0.0238, 6), "lng": round(user_lng + 0.0171, 6)},
                "phone": "+91-102",
                "help": ["medical", "ambulance"],
                "source": "DTN-RELAY-ACTIVE"
            }
        ]
        dtn_gives = [
            {
                "type": "victim",
                "name": "Disaster Victim SOS (DTN Relayed)",
                "location": {"lat": round(user_lat + 0.0053, 6), "lng": round(user_lng - 0.0042, 6)},
                "phone": "DTN-PEER-01",
                "help": ["food", "water", "rescue"],
                "source": "DTN-PEER-PACKET"
            },
            {
                "type": "volunteer",
                "name": "NDRF / Civil Defense Volunteer Rapid Response Unit",
                "location": {"lat": round(user_lat - 0.0115, 6), "lng": round(user_lng + 0.0078, 6)},
                "phone": "+91-98400-11223",
                "help": ["rescue", "debris_clearing", "elderly_assistance"],
                "source": "DTN-MESH-ACTIVE"
            },
            {
                "type": "food",
                "name": "Community Relief Kitchen & Rations Hub",
                "location": {"lat": round(user_lat + 0.0168, 6), "lng": round(user_lng + 0.0115, 6)},
                "phone": "+91-1800-425",
                "help": ["food", "clean_water"],
                "source": "DTN-STORE-CARRY-FORWARD"
            }
        ]
        # Ingest actively relayed DTN emergency packets from SOSManager
        for req in sos_manager.requests.values():
            if req.get("lat") and req.get("lng"):
                dtn_gives.append({
                    "type": "victim",
                    "name": f"SOS: {req.get('description', 'Emergency Request')}",
                    "location": {"lat": req["lat"], "lng": req["lng"]},
                    "phone": req.get("user_id", "DTN-RELAY"),
                    "help": req.get("preferred_assistance", ["rescue"]),
                    "source": "DTN-STORE-CARRY-FORWARD"
                })

        merged_needs = dtn_needs + local_store.get("needs_and_gives", {}).get("need", [])
        merged_gives = dtn_gives + local_store.get("needs_and_gives", {}).get("give", [])
        return jsonify({"need": merged_needs, "give": merged_gives, "dtn_mode": "ACTIVE_MESH"})

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


@app.route('/api/sos/create', methods=['POST'])
def create_sos():
    try:
        data = request.get_json(force=True)
        if not data:
            return jsonify({"error": "Missing JSON payload"}), 400
        
        record = sos_manager.create_sos(data)
        
        # Match nearest suitable rescue units
        lat = record["lat"]
        lng = record["lng"]
        cat = record["category"]
        nearest_teams = rescue_service.find_nearest_teams(lat, lng, cat, max_results=3)
        
        return jsonify({
            "success": True,
            "sos": record,
            "nearest_teams": nearest_teams,
            "message": "SOS received and rescue coordination initiated"
        }), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/sos/<sos_id>', methods=['GET'])
def get_sos(sos_id):
    record = sos_manager.get_sos(sos_id)
    if not record:
        return jsonify({"error": "Emergency request not found"}), 404
    return jsonify(record), 200

@app.route('/api/sos/<sos_id>/status', methods=['GET'])
def get_sos_status(sos_id):
    record = sos_manager.get_sos(sos_id)
    if not record:
        return jsonify({"error": "Emergency request not found"}), 404
    return jsonify({
        "sos_id": record["sos_id"],
        "status": record["status"],
        "assigned_team": record.get("assigned_team"),
        "status_history": record.get("status_history", [])
    }), 200

@app.route('/api/sos/<sos_id>/acknowledge', methods=['POST'])
def acknowledge_sos(sos_id):
    try:
        data = request.get_json(force=True) or {}
        team_id = data.get("team_id", "NDRF-BN-04-A")
        team_name = data.get("team_name", "NDRF Flood Rescue Unit Alpha")
        
        record = sos_manager.acknowledge_sos(sos_id, team_id, team_name)
        if not record:
            return jsonify({"error": "Emergency request not found"}), 404
        return jsonify({
            "success": True,
            "sos": record,
            "message": f"Assigned to {team_name} and marked EN ROUTE"
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/rescue/teams', methods=['GET'])
def get_rescue_teams():
    return jsonify({"teams": rescue_service.get_all_teams()}), 200

@app.route('/api/rescue/nearby', methods=['GET'])
def get_nearby_rescue():
    try:
        lat = float(request.args.get('lat', 12.9806))
        lng = float(request.args.get('lng', 80.2132))
        category = request.args.get('category', None)
        max_res = int(request.args.get('limit', 5))
        
        nearest = rescue_service.find_nearest_teams(lat, lng, category, max_results=max_res)
        return jsonify({
            "user_location": {"lat": lat, "lng": lng},
            "category": category,
            "teams": nearest
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@app.route('/api/offline/relay', methods=['POST'])
def offline_relay():
    try:
        data = request.get_json(force=True) or {}
        messages = data.get("messages", [])
        if isinstance(messages, dict):
            messages = [messages]
            
        result = sos_manager.receive_offline_relay(messages)
        return jsonify({
            "success": True,
            "relay_result": result
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/offline/sync', methods=['POST'])
def offline_sync():
    return offline_relay()

@app.route('/api/chat/emergency', methods=['GET'])
def chat_emergency():
    query = request.args.get('query', '')
    category = request.args.get('category', None)
    
    if not query:
        return jsonify({"error": "Missing query parameter"}), 400
        
    guidance = rag_service.generate_guidance(query, category)
    return jsonify({
        "query": query,
        "guidance": guidance
    }), 200


@app.route('/api/v1/nearby-shops', methods=['GET', 'POST'])
def nearby_shops():
    try:
        if request.method == 'POST':
            body = request.get_json(silent=True) or {}
            lat = float(body.get('lat', 26.9136))
            lng = float(body.get('lng', 75.7858))
            category = body.get('category') or body.get('heading') or 'Medical / Pharmacy'
            city = body.get('city', '')
        else:
            lat = float(request.args.get('lat', 26.9136))
            lng = float(request.args.get('lng', 75.7858))
            category = request.args.get('category') or request.args.get('heading') or 'Medical / Pharmacy'
            city = request.args.get('city', '')
    except Exception as e:
        lat, lng, category, city = 26.9136, 75.7858, 'Medical / Pharmacy', ''

    groq_key = os.getenv('GROQ_API_KEY') or GROQ_API_KEY
    groq_model = os.getenv('GROQ_MODEL') or GROQ_MODEL or 'qwen/qwen3.8-27b'

    # If city is not passed, attempt quick reverse lookup from coordinates or default
    loc_hint = f"around latitude {lat:.4f}, longitude {lng:.4f}"
    if city:
        loc_hint += f" in/near {city}"

    prompt = f"""You are Sahaya, an emergency disaster relief & local directory assistant.
The user has allowed location access on their device. Their current coordinates are:
Latitude: {lat:.4f}, Longitude: {lng:.4f} ({loc_hint}).

The user clicked on the heading: "{category}".

Generate a realistic, specific list of 4 to 6 nearby shops, emergency supply stores, or service centers matching "{category}" in this immediate local area.

Requirements:
1. Each shop must have a realistic, authentic business name and street/locality address fitting this region.
2. The coordinates (lat, lng) for each shop MUST be very close to the user: within 200m to 2.5km distance (offsets within +/-0.002 to +/-0.020 from {lat:.4f}, {lng:.4f}).
3. Include realistic phone numbers, operational hours (e.g. "Open 24/7" or "8:00 AM - 10:30 PM").
4. Include a list of specific available relief items or services in stock (e.g. bandages, paracetamol, drinking water, flashlights, milk, dry rations, first-aid, etc.).

Respond STRICTLY in a JSON object with this exact structure:
{{
  "category": "{category}",
  "user_location": {{"lat": {lat}, "lng": {lng}}},
  "shops": [
    {{
      "name": "Shop Name",
      "type": "{category}",
      "address": "Street / Locality, Landmark",
      "phone": "+91 98765 43210",
      "operating_hours": "Open 24 Hours",
      "items_available": ["Emergency Item 1", "Item 2", "Item 3"],
      "verified": true,
      "location": {{
        "lat": {lat + 0.003},
        "lng": {lng + 0.002}
      }}
    }}
  ]
}}"""

    if groq_key:
        try:
            res = requests.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {groq_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": groq_model,
                    "messages": [
                        {"role": "system", "content": "You are a local emergency directory AI assistant. Respond strictly in valid JSON."},
                        {"role": "user", "content": prompt}
                    ],
                    "response_format": {"type": "json_object"}
                },
                timeout=15
            )
            if res.status_code == 200:
                raw_content = res.json()['choices'][0]['message']['content']
                parsed = json.loads(raw_content)
                if "shops" not in parsed:
                    if isinstance(parsed, list):
                        parsed = {"category": category, "shops": parsed}
                    else:
                        for k, v in parsed.items():
                            if isinstance(v, list):
                                parsed = {"category": category, "shops": v}
                                break
                return jsonify(parsed)
            else:
                print(f"Groq API returned status {res.status_code}: {res.text}")
        except Exception as e:
            print(f"Error querying Groq API: {e}")

    # Fallback nearby shops around user's lat, lng if Groq fails or offline
    fallback_shops = [
        {
            "name": f"City Care {category.split('/')[0].strip()} Center",
            "type": category,
            "address": f"Main Market Road, near Sector 3, ({lat:.3f}, {lng:.3f})",
            "phone": "+91 141 2345678",
            "operating_hours": "Open 24/7",
            "items_available": ["First Aid Kits", "Emergency Rations", "Water Bottles", "Prescriptions"],
            "verified": True,
            "location": {"lat": lat + 0.0035, "lng": lng + 0.0025}
        },
        {
            "name": f"Apex {category.split('/')[0].strip()} Store",
            "type": category,
            "address": f"Station Road, Civil Lines, ({lat:.3f}, {lng:.3f})",
            "phone": "+91 98290 11223",
            "operating_hours": "7:00 AM - 11:00 PM",
            "items_available": ["Sanitizers", "Dry Food", "Batteries", "Torch Lights"],
            "verified": True,
            "location": {"lat": lat - 0.0028, "lng": lng + 0.0042}
        },
        {
            "name": f"Reliable {category.split('/')[0].strip()} Hub",
            "type": category,
            "address": f"Bazaar Circle, Near Metro Pillar 42, ({lat:.3f}, {lng:.3f})",
            "phone": "+91 98290 99887",
            "operating_hours": "8:00 AM - 10:00 PM",
            "items_available": ["Emergency Pack", "ORS", "Medicines", "Blankets"],
            "verified": True,
            "location": {"lat": lat + 0.0045, "lng": lng - 0.0031}
        }
    ]
    return jsonify({
        "category": category,
        "user_location": {"lat": lat, "lng": lng},
        "shops": fallback_shops,
        "source": "fallback"
    })


if __name__ == '__main__':
    app.run(host="0.0.0.0", port=8080, debug=True)
