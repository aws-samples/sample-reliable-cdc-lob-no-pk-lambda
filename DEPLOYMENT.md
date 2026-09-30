# Lambda deployment notes

The sample imports `pyodbc` and `psycopg2-binary`. `pyodbc` requires compatible native components and the Microsoft ODBC Driver for SQL Server. `psycopg2-binary` is distributed as a prebuilt wheel that bundles its PostgreSQL client dependencies, but the selected wheel must still be compatible with the Lambda runtime and instruction-set architecture.

Do not build the deployment artifact by installing dependencies on Windows or macOS and zipping that local directory. Package for the Linux runtime and architecture used by the Lambda function.

## Recommended approach for this sample

Use either:

1. a Lambda container image based on an AWS Lambda Python base image, installing the Microsoft ODBC Driver for SQL Server plus the Python dependencies in the image; or
2. Lambda layers/deployment packages built in a compatible Linux environment, with the required ODBC runtime libraries included.

The container-image approach is generally easier to reproduce when `pyodbc` and the Microsoft SQL Server ODBC driver are required.

The repository intentionally does not include a prebuilt binary layer or container image because binary artifacts are runtime/architecture specific and should be built and security-reviewed in the publishing environment.

## Required runtime components

- Python runtime compatible with the selected Lambda base image
- `pyodbc`
- Microsoft ODBC Driver for SQL Server
- `psycopg2-binary` wheel compatible with the selected Lambda runtime and architecture
- CA certificates required to validate both database TLS connections

## Security configuration

- Keep `Encrypt=yes;TrustServerCertificate=no` for SQL Server unless your approved environment requires another validated configuration.
- Keep PostgreSQL `sslmode=verify-full` and ensure the trust store contains the CA needed to validate the Aurora certificate chain.
- Store credentials in AWS Secrets Manager.
- Grant the Lambda role only the Secrets Manager/logging/network permissions it requires.
- Use least-privilege SQL Server and PostgreSQL database principals.
- Configure reserved concurrency to `1` for this single checkpoint stream.

Before publication, build and test the deployment artifact in the same runtime/architecture combination documented in the blog.
