import os
from flask import Flask, request, jsonify
from flask_cors import CORS
from openai import OpenAI
from pathlib import Path
from dotenv import load_dotenv
from typing import Union, List
from mem0 import Memory
from faster_whisper import WhisperModel
load_dotenv()

model_size = "large-v3"
openai_client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
mem0 = Memory()
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes



# Create uploads directory if it doesn't exist
UPLOAD_FOLDER = Path(__file__).parent.joinpath('uploads')

if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)


@app.route('/query-memory', methods=['GET'])
def chat_with_memories(query: str, user_id: str = "default_user") -> str:
    # Retrieve relevant memories
    relevant_memories = mem0.search(query=query, user_id=user_id)
    memories_str = "\n".join(f"- {entry['memory']}" for entry in relevant_memories)

    # Generate Assistant response
    system_prompt = f"You are a helpful AI. Answer the question based on query and memories.\nUser Memories:\n{memories_str}"
    messages = [{"role": "system", "content": system_prompt}, {"role": "user", "content": query}]
    response = openai_client.chat.completions.create(model="gpt-4o-mini", messages=messages)
    assistant_response = response.choices[0].message.content

    return jsonify({'assistant_response': assistant_response})


def process_audio(file_path, user="default_user"):
    print("Processing audio file...")
    model = WhisperModel(model_size, device="cpu", compute_type="int8")

    # or run on GPU with INT8
    # model = WhisperModel(model_size, device="cuda", compute_type="int8_float16")
    # or run on CPU with INT8
    # model = WhisperModel(model_size, device="cpu", compute_type="int8")

    segments, info = model.transcribe(file_path, beam_size=5)

    print("Detected language '%s' with probability %f" % (info.language, info.language_probability))

    for segment in segments:
        print("adding segment to memory:",segment.text)
        mem0.add(segment.text, user_id=user, metadata={"category": "chat"})


@app.route('/upload-audio', methods=['POST'])
def upload_audio():
    print("IN PYTHON")
    if 'audio' not in request.files:
        return {'error': 'No audio file provided'}, 400
    
    audio_file = request.files['audio']
    if audio_file.filename == '':
        return {'error': 'No selected file'}, 400
    
    # Save the file
    file_path = os.path.join(UPLOAD_FOLDER, audio_file.filename)
    audio_file.save(file_path)
    
    # Process the audio file
    process_audio(file_path)
    return jsonify({'message': f'File uploaded successfully at {audio_file.filename}'})



if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
    #TODO: Get queue to work well from flutter to python(see why multiple posts are running.)