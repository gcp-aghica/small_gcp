# small-gcp

Учебный FastAPI-сервис `demo-api` для отработки trunk-based CI/CD на Cloud Run перед переносом в `calculations-api`.

```bash
make install && make test
```
```bash
make build && docker run --rm -p 8000:8000 -e API_TOKEN=local local/demo-api:dev
```

Настройка инфраструктуры руками: [GCP](docs/setup-gcp-ui.md), [GitHub](docs/setup-github-ui.md), [teardown](docs/teardown-ui.md).
Полное описание flow появится после первого автодеплоя.
