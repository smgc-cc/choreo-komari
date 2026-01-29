package flags

var (
	// 数据库配置
	DatabaseType string // 数据库类型：sqlite, mysql
	DatabaseFile string // SQLite数据库文件路径
	DatabaseHost string // MySQL/其他数据库主机地址
	DatabasePort string // MySQL/其他数据库端口
	DatabaseUser string // MySQL/其他数据库用户名
	DatabasePass string // MySQL/其他数据库密码
	DatabaseName string // MySQL/其他数据库名称

	Listen   string // HTTP 服务监听地址
	WsListen string // WebSocket 独立监听地址（可选，用于 Choreo 等平台）
)
