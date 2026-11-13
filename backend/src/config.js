// All configuration comes from environment variables.
//
// Locally, docker-compose sets them from your .env file.
// On ECS, plain values (DB_HOST, DB_NAME...) are set in the task definition, and
// DB_USER / DB_PASSWORD are injected by ECS from AWS Secrets Manager at container
// start. The app never calls Secrets Manager itself, so its task role needs no
// secret permissions at all (least privilege).

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 4000),
  db: {
    host: required('DB_HOST'),
    port: Number(process.env.DB_PORT ?? 5432),
    database: required('DB_NAME'),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    // RDS requires TLS. Locally (docker Postgres) it's off.
    ssl: process.env.DB_SSL === 'true',
    // Path to the RDS certificate bundle, baked into the Docker image, so the
    // connection verifies it is really talking to RDS (not just "encrypted").
    sslCaPath: process.env.DB_SSL_CA_PATH,
  },
};
