import React, { useState, useEffect } from 'react';
import { Cat, Dog, RefreshCw } from 'lucide-react';

export default function App() {
  const [results, setResults] = useState({ cats: 0, dogs: 0, jobs: [] });
  const [voting, setVoting] = useState(null);
  const [error, setError] = useState(null);
  
  const API_URL = 'http://localhost:8000';

  const fetchResults = async () => {
    try {
      const res = await fetch(`${API_URL}/results`);
      const data = await res.json();
      setResults(data);
      setError(null);
    } catch (err) {
      setError('Failed to fetch results');
    }
  };

  useEffect(() => {
    fetchResults();
    const interval = setInterval(fetchResults, 2000);
    return () => clearInterval(interval);
  }, []);

  const vote = async (choice) => {
    setVoting(choice);
    try {
      const res = await fetch(`${API_URL}/vote`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ choice })
      });
      if (!res.ok) throw new Error('Vote failed');
      await fetchResults();
      setError(null);
    } catch (err) {
      setError(`Failed to vote for ${choice}`);
    } finally {
      setVoting(null);
    }
  };

  const total = results.cats + results.dogs;
  const catsPercent = total ? Math.round((results.cats / total) * 100) : 0;
  const dogsPercent = total ? Math.round((results.dogs / total) * 100) : 0;

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-50 to-blue-50 p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-5xl font-bold text-center mb-2 text-gray-800">
          Cats vs Dogs
        </h1>
        <p className="text-center text-gray-600 mb-8">Cast your vote!</p>
        <p className="text-center text-gray-600 mb-8">Daily reset at midnight!</p>
        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-6">
            {error}
          </div>
        )}

        <div className="grid md:grid-cols-2 gap-6 mb-8">
          <button
            onClick={() => vote('cats')}
            disabled={voting !== null}
            className="bg-white rounded-2xl shadow-lg p-8 hover:shadow-xl transition-all transform hover:scale-105 disabled:opacity-50 disabled:transform-none"
          >
            <Cat className="w-24 h-24 mx-auto mb-4 text-orange-500" />
            <h2 className="text-3xl font-bold text-gray-800 mb-2">Cats</h2>
            <div className="text-5xl font-bold text-orange-500 mb-2">
              {results.cats}
            </div>
            <div className="w-full bg-gray-200 rounded-full h-3">
              <div
                className="bg-orange-500 h-3 rounded-full transition-all"
                style={{ width: `${catsPercent}%` }}
              />
            </div>
            <div className="text-gray-600 mt-2">{catsPercent}%</div>
          </button>

          <button
            onClick={() => vote('dogs')}
            disabled={voting !== null}
            className="bg-white rounded-2xl shadow-lg p-8 hover:shadow-xl transition-all transform hover:scale-105 disabled:opacity-50 disabled:transform-none"
          >
            <Dog className="w-24 h-24 mx-auto mb-4 text-blue-500" />
            <h2 className="text-3xl font-bold text-gray-800 mb-2">Dogs</h2>
            <div className="text-5xl font-bold text-blue-500 mb-2">
              {results.dogs}
            </div>
            <div className="w-full bg-gray-200 rounded-full h-3">
              <div
                className="bg-blue-500 h-3 rounded-full transition-all"
                style={{ width: `${dogsPercent}%` }}
              />
            </div>
            <div className="text-gray-600 mt-2">{dogsPercent}%</div>
          </button>
        </div>

        <div className="bg-white rounded-xl shadow-lg p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-xl font-bold text-gray-800">Recent Jobs</h3>
            <button
              onClick={fetchResults}
              className="p-2 hover:bg-gray-100 rounded-full"
            >
              <RefreshCw className="w-5 h-5" />
            </button>
          </div>
          <div className="space-y-2 max-h-64 overflow-y-auto">
            {results.jobs.slice(0, 10).map((job) => (
              <div
                key={job.id}
                className="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
              >
                <span className="font-medium capitalize">{job.choice}</span>
                <span
                  className={`px-3 py-1 rounded-full text-sm ${
                    job.status === 'completed'
                      ? 'bg-green-100 text-green-800'
                      : job.status === 'processing'
                      ? 'bg-yellow-100 text-yellow-800'
                      : 'bg-gray-100 text-gray-800'
                  }`}
                >
                  {job.status}
                </span>
              </div>
              
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}