import {existsSync} from 'node:fs';
if(existsSync('.env.local'))process.loadEnvFile('.env.local');
import {defineConfig} from 'vitest/config';
export default defineConfig({test:{include:['tests/integration/**/*.test.ts'],environment:'node',testTimeout:30000,hookTimeout:60000,fileParallelism:false}});
