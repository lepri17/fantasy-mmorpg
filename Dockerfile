# The game server (server/) for cloud hosting (ROADMAP N13).
# It needs the game data from client/data and the meadow scene.
FROM python:3.12-slim
WORKDIR /app
COPY server/requirements.txt server/requirements.txt
RUN pip install --no-cache-dir -r server/requirements.txt "psycopg[binary]>=3.1"
COPY server server
COPY client/data client/data
COPY client/scenes/maps/field.tscn client/scenes/maps/field.tscn
ENV PORT=8765
EXPOSE 8765
CMD ["python", "-m", "server"]
