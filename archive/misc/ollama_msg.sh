#!/bin/bash
curl -s http://localhost:11434/api/chat -d '{
  "model": "lbm-embodied",
  "messages": [{"role": "user", "content": "Continue the journey into the heart of the lattice."}],
  "stream": false
}' 2>/dev/null | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['message']['content'])"