from fastapi import FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pika
import psycopg2
from psycopg2.extras import RealDictCursor
import json
import os
import uuid

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5432'),
    'database': os.getenv('DB_NAME', 'voting'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'postgres')
}

RABBITMQ_HOST = os.getenv('RABBITMQ_HOST', 'localhost')
QUEUE_NAME = 'votes'

class VoteRequest(BaseModel):
    choice: str

def get_db():
    return psycopg2.connect(**DB_CONFIG)

def get_rabbitmq():
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host=RABBITMQ_HOST)
    )
    channel = connection.channel()
    channel.queue_declare(queue=QUEUE_NAME, durable=True)
    return connection, channel

@app.post("/vote")
async def vote(request: VoteRequest):
    if request.choice not in ['cats', 'dogs']:
        raise HTTPException(400, "Invalid choice")
    
    job_id = str(uuid.uuid4())
    
    # Store job in DB
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO jobs (id, choice, status) VALUES (%s, %s, %s)",
            (job_id, request.choice, 'pending')
        )
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        raise HTTPException(500, f"Database error: {str(e)}")
    
    # Send to queue
    try:
        connection, channel = get_rabbitmq()
        message = json.dumps({'job_id': job_id, 'choice': request.choice})
        channel.basic_publish(
            exchange='',
            routing_key=QUEUE_NAME,
            body=message,
            properties=pika.BasicProperties(delivery_mode=2)
        )
        connection.close()
    except Exception as e:
        raise HTTPException(500, f"Queue error: {str(e)}")
    
    return {'job_id': job_id, 'status': 'pending'}

@app.get("/results")
async def results():
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get vote counts
        cur.execute("SELECT choice, count FROM votes ORDER BY choice")
        votes = {row['choice']: row['count'] for row in cur.fetchall()}
        
        # Get recent jobs
        cur.execute(
            "SELECT id, choice, status, created_at FROM jobs ORDER BY created_at DESC LIMIT 20"
        )
        jobs = cur.fetchall()
        
        cur.close()
        conn.close()
        
        return {
            'cats': votes.get('cats', 0),
            'dogs': votes.get('dogs', 0),
            'jobs': jobs
        }
    except Exception as e:
        raise HTTPException(500, f"Database error: {str(e)}")

@app.post("/reset")
async def reset_votes(authorization: str = Header(...)):
    if authorization != "Bearer my-secret-key":  # Replace with your secret key
        raise HTTPException(401, "Unauthorized")
    conn = get_db()
    cur = conn.cursor()
    cur.execute("TRUNCATE votes, jobs RESTART IDENTITY")
    conn.commit()
    cur.close()
    conn.close()
    return {"message": "Votes and jobs reset"}

# 0 0 * * * curl -X POST https://api.yourdomain.com/reset?key=my-secret-key