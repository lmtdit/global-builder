# TMS全局组件库开发构建工具
--------------
by Pang.J.G

这里是TMS全局组件库，存放全局依赖的静态资源，包括全局依赖的js库，css样式、字体或图片等。

## 创建配置config.json

```json
{
    "env": "local",
    "prefix": "tms.",
    "hashLen": 10,
    "cdnDomain": "tmstatics.xxx.com"
}

```
## 使用

### 安装依赖
```
npm install
```

### 查看命令

```
gulp -h  # 查看构建命令支持的参数
gulp -T  # 查看gulp支持的任务
```

### 开发和发布

```
gulp init  # 初始化项目

gulp  # 进入开发状态

gulp --e test # 发布test

gulp --e rc # 发布rc

gulp --e www # 发布生产
```



## The End.
