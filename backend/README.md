# 后端（FastAPI + MySQL + JWT）

快速可部署的后端骨架，支持：
- 用户注册/登录（JWT）
- 标点 CRUD
- 用户隔离 + 简单权限（仅本人可改/删）

## 目录结构
```
backend/
  app/
    main.py
    config.py
    db.py
    models.py
    schemas.py
    auth.py
  requirements.txt
  Dockerfile
  docker-compose.yaml
  .env.example
```

## 启动（Docker）
1. 复制并填写环境变量：
   - 复制 `.env.example` 为 `.env`
2. 运行：
   - `docker compose up -d`

API 将运行在：`http://localhost:8000`

## 关键接口
### 注册
`POST /auth/register`
```json
{ "username": "user1", "password": "123456" }
```

### 登录
`POST /auth/login`
```json
{ "username": "user1", "password": "123456" }
```

返回：
```json
{ "access_token": "...", "token_type": "bearer" }
```

### 标点
- `GET /markers`
- `POST /markers`
- `PUT /markers/{id}`
- `DELETE /markers/{id}`

请求头：
`Authorization: Bearer <token>`
