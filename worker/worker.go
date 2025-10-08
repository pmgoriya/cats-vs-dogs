package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/streadway/amqp"
)

type Message struct {
	JobID  string `json:"job_id"`
	Choice string `json:"choice"`
}

func main() {
	dbHost := getEnv("DB_HOST", "localhost")
	dbPort := getEnv("DB_PORT", "5432")
	dbName := getEnv("DB_NAME", "voting")
	dbUser := getEnv("DB_USER", "postgres")
	dbPass := getEnv("DB_PASSWORD", "postgres")
	rabbitHost := getEnv("RABBITMQ_HOST", "localhost")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPass, dbName)
	
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	conn, err := amqp.Dial(fmt.Sprintf("amqp://guest:guest@%s:5672/", rabbitHost))
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		log.Fatal(err)
	}
	defer ch.Close()

	q, err := ch.QueueDeclare("votes", true, false, false, false, nil)
	if err != nil {
		log.Fatal(err)
	}

	msgs, err := ch.Consume(q.Name, "", false, false, false, false, nil)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("Worker started. Waiting for messages...")

	for msg := range msgs {
		var m Message
		if err := json.Unmarshal(msg.Body, &m); err != nil {
			log.Printf("Error parsing message: %v", err)
			msg.Nack(false, false)
			continue
		}

		log.Printf("Processing job %s: %s", m.JobID, m.Choice)

		// Update job status to processing
		_, err := db.Exec("UPDATE jobs SET status = 'processing' WHERE id = $1", m.JobID)
		if err != nil {
			log.Printf("Error updating job: %v", err)
			msg.Nack(false, true)
			continue
		}

		// Simulate work
		time.Sleep(500 * time.Millisecond)

		// Update vote count
		_, err = db.Exec(`
			INSERT INTO votes (choice, count) VALUES ($1, 1)
			ON CONFLICT (choice) DO UPDATE SET count = votes.count + 1
		`, m.Choice)
		if err != nil {
			log.Printf("Error updating votes: %v", err)
			msg.Nack(false, true)
			continue
		}

		// Mark job completed
		_, err = db.Exec("UPDATE jobs SET status = 'completed' WHERE id = $1", m.JobID)
		if err != nil {
			log.Printf("Error completing job: %v", err)
			msg.Nack(false, true)
			continue
		}

		msg.Ack(false)
		log.Printf("Completed job %s", m.JobID)
	}
}

func getEnv(key, def string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return def
}