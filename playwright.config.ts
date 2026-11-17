import {existsSync} from 'node:fs';
if(existsSync('.env.local'))process.loadEnvFile('.env.local');
import {defineConfig,devices} from '@playwright/test';
export default defineConfig({testDir:'tests/e2e',timeout:30000,fullyParallel:true,forbidOnly:!!process.env.CI,retries:process.env.CI?1:0,reporter:[['list'],['html',{open:'never'}]],use:{baseURL:process.env.PLAYWRIGHT_BASE_URL??'http://localhost:3000',trace:'retain-on-failure',screenshot:'only-on-failure',launchOptions:{...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE?{executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE}:{}),args:['--no-sandbox']}},projects:[{name:'desktop',use:{...devices['Desktop Chrome']}},{name:'mobile',use:{...devices['iPhone 13'],defaultBrowserType:'chromium'}}]});
