## Credits / Attribution

This project is based on the following open-source work:

- Original Repository: [shoppingmall_project](https://github.com/dbswhd4932/shoppingmall_project)
- Author: dbswhd4932

Modifications:
- Security hardening
- DevSecOps pipeline integration
- Kubernetes deployment support

## Environments (local vs staging)
### local
- Profile: `local`
- Config: `application-local.yml` + local env vars
- Image storage: local filesystem (`/uploads`)
- S3: disabled (`S3Service` not active)
- Logs: console + local files

### staging
- Profile: `staging`
- Config: K8s ConfigMap + Secret
- Image storage: S3 URL stored (S3 upload enabled)
- S3: enabled
- Logs: console + files + Logstash attempt

2026.01.08 test12
//test
//test 0435
//test 0518
//test 0258
//test 0311
//test 0316
//test 0335
//test 0345
//test

