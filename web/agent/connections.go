package agent

import (
	"sync"
	"time"

	v1 "github.com/komari-monitor/komari/protocol/v1"
	"github.com/komari-monitor/komari/web/connection"
)

var (
	connectedClients = make(map[string]*connection.SafeConn)
	latestReport     = make(map[string]*v1.Report)
	// presenceOnly stores online state for non-WebSocket agents
	presenceOnly = make(map[string]struct {
		id     int64
		expire time.Time
	})
	mu = sync.RWMutex{}
)

func GetConnectedClients() map[string]*connection.SafeConn {
	mu.RLock()
	defer mu.RUnlock()
	clientsCopy := make(map[string]*connection.SafeConn)
	for k, v := range connectedClients {
		clientsCopy[k] = v
	}
	return clientsCopy
}

func SetConnectedClients(uuid string, conn *connection.SafeConn) {
	mu.Lock()
	defer mu.Unlock()
	connectedClients[uuid] = conn
}

func DeleteClientConditionally(uuid string, connToRemove *connection.SafeConn) {
	mu.Lock()
	defer mu.Unlock()
	if currentConn, exists := connectedClients[uuid]; exists && currentConn == connToRemove {
		delete(connectedClients, uuid)
	}
}

func DeleteConnectedClients(uuid string) {
	mu.Lock()
	defer mu.Unlock()
	delete(connectedClients, uuid)
}

func GetAllOnlineUUIDs() []string {
	mu.RLock()
	defer mu.RUnlock()
	set := make(map[string]struct{})
	for k := range connectedClients {
		set[k] = struct{}{}
	}
	now := time.Now()
	for k, v := range presenceOnly {
		if v.expire.After(now) {
			set[k] = struct{}{}
		}
	}
	res := make([]string, 0, len(set))
	for k := range set {
		res = append(res, k)
	}
	return res
}

func GetLatestReport() map[string]*v1.Report {
	mu.RLock()
	defer mu.RUnlock()
	reportCopy := make(map[string]*v1.Report)
	for k, v := range latestReport {
		reportCopy[k] = v
	}
	return reportCopy
}

func SetLatestReport(uuid string, report *v1.Report) {
	mu.Lock()
	defer mu.Unlock()
	latestReport[uuid] = report
}

func DeleteLatestReport(uuid string) {
	mu.Lock()
	defer mu.Unlock()
	delete(latestReport, uuid)
}

// SetPresence sets or clears presence for non-WebSocket agents.
func SetPresence(uuid string, connectionID int64, present bool) {
	mu.Lock()
	defer mu.Unlock()
	if present {
		presenceOnly[uuid] = struct {
			id     int64
			expire time.Time
		}{id: connectionID, expire: time.Now().Add(20 * time.Second)}
		return
	}
	if cur, ok := presenceOnly[uuid]; ok && cur.id == connectionID {
		delete(presenceOnly, uuid)
	}
}

// KeepAlivePresence refreshes the presence TTL for non-WebSocket agents.
func KeepAlivePresence(uuid string, connectionID int64, ttl time.Duration) {
	mu.Lock()
	defer mu.Unlock()
	presenceOnly[uuid] = struct {
		id     int64
		expire time.Time
	}{id: connectionID, expire: time.Now().Add(ttl)}
}

// DispatchPing sends a ping task to a connected agent (legacy protocol only).
func DispatchPing(uuid string, pingMessage any) bool {
	conn := GetConnectedClients()[uuid]
	if conn == nil {
		return false
	}
	if conn.WriteJSON(pingMessage) == nil {
		return true
	}
	return false
}
