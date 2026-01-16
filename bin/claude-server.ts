#!/usr/bin/env node
import { App } from 'aws-cdk-lib';
import { ClaudeServerStack } from '../lib/claude-server-stack.js';
import { config } from '../config/config.js';

const app = new App();

new ClaudeServerStack(app, 'ClaudeServerStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: config.region,
  },
  description: 'Remote development environment with code-server and Claude Code',
});
