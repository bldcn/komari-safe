package jsonrpc

import (
	"context"
	"strconv"

	"github.com/komari-monitor/komari/database/dbcore"
	"github.com/komari-monitor/komari/database/models"
	"github.com/komari-monitor/komari/pkg/rpc"
	"github.com/komari-monitor/komari/utils/messageSender"
)

// admin.system.go
// 系统/运维类 RPC2 方法（admin 命名空间）：日志、测试。

func init() {
	reg("getLogs", adminGetLogs, "Get audit logs (paged)")
	reg("testSendMessage", adminTestSendMessage, "Send a test notification")
}

func adminGetLogs(_ context.Context, req *rpc.JsonRpcRequest) (any, *rpc.JsonRpcError) {
	var params struct {
		Limit string `json:"limit"`
		Page  string `json:"page"`
	}
	req.BindParams(&params)
	if params.Limit == "" {
		params.Limit = "100"
	}
	if params.Page == "" {
		params.Page = "1"
	}
	limitInt, err := strconv.Atoi(params.Limit)
	if err != nil || limitInt <= 0 {
		return nil, rpc.MakeError(rpc.InvalidParams, "Invalid limit: "+params.Limit, nil)
	}
	pageInt, err := strconv.Atoi(params.Page)
	if err != nil || pageInt <= 0 {
		return nil, rpc.MakeError(rpc.InvalidParams, "Invalid page: "+params.Page, nil)
	}
	db := dbcore.GetDBInstance()
	var logs []models.Log
	offset := (pageInt - 1) * limitInt
	var total int64
	if err := db.Model(&models.Log{}).Count(&total).Error; err != nil {
		return nil, rpc.MakeError(rpc.InternalError, "Failed to count logs: "+err.Error(), nil)
	}
	if err := db.Order("time desc").Limit(limitInt).Offset(offset).Find(&logs).Error; err != nil {
		return nil, rpc.MakeError(rpc.InternalError, "Failed to retrieve logs: "+err.Error(), nil)
	}
	return map[string]any{"logs": logs, "total": total}, nil
}

func adminTestSendMessage(_ context.Context, _ *rpc.JsonRpcRequest) (any, *rpc.JsonRpcError) {
	err := messageSender.SendEvent(models.EventMessage{
		Event:   "Test",
		Message: "This is a test message from Komari.",
	})
	if err != nil {
		return nil, rpc.MakeError(rpc.InternalError, "Failed to send message: "+err.Error(), nil)
	}
	return nil, nil
}
