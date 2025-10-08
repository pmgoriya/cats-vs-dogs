-- Create database (run as postgres user)
-- CREATE DATABASE voting;

-- Connect to voting database
\c voting

-- Votes table
CREATE TABLE IF NOT EXISTS votes (
    choice VARCHAR(10) PRIMARY KEY,
    count INTEGER NOT NULL DEFAULT 0
);

-- Jobs table
CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY,
    choice VARCHAR(10) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_jobs_created ON jobs(created_at DESC);
CREATE INDEX idx_jobs_status ON jobs(status);

-- Seed data
INSERT INTO votes (choice, count) VALUES ('cats', 0), ('dogs', 0)
ON CONFLICT (choice) DO NOTHING;