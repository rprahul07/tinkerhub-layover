// Resets data/db.json to the seed (drops user-created journeys, saves and likes).
import { config } from '../src/config.js';
import { Store } from '../src/store.js';

new Store(config.dataDir).reset();
console.log('Database reset to seed.');
