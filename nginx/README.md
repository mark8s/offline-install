# Nginx 

## 安装
```shell
sudo yum install -y epel-release
sudo yum -y update
sudo yum install -y nginx
```

## nginx.conf配置

```shell
    server {
        listen      80;
        server_name demo.solarmesh.local;
        client_max_body_size 500m;
    
        location / {
            proxy_pass http://192.168.112.149:30880;
            proxy_set_header Host $proxy_host; 
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Upgrade $http_upgrade; # websocket
            proxy_set_header Connection "upgrade"; # websocket
            rewrite (.*)//(.*) $1/$2 permanent;
            proxy_http_version 1.1;
        }
    }

    server {
        listen       80;
        server_name  bookinfo.solarmesh.local;
        root         /usr/share/nginx/html;

        location / {
            proxy_pass http://192.168.112.149:30201/;
            proxy_set_header Host $proxy_host; # 修改转发请求头，让8080端口的应用可以受到真实的请求
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Upgrade $http_upgrade; # websocket
            proxy_set_header Connection "upgrade"; # websocket
            rewrite (.*)//(.*) $1/$2 permanent;
            proxy_http_version 1.1;
        }
    }
```

### 启用开机启动 Nginx 
```shell
systemctl enable nginx
```

### 常用命令
```shell
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl status nginx
```
