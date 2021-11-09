# you could add this line to your puma config
bind ENV.fetch("PUMA_BIND", "tcp://127.0.0.1:3000")
