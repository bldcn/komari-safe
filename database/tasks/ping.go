package tasks

import (
	"log"
	"sort"
	"time"

	"github.com/komari-monitor/komari/database/dbcore"
	"github.com/komari-monitor/komari/database/models"
	"gorm.io/gorm/clause"
)

// AddPingTask creates a new ping task.
func AddPingTask(clients []string, defaultOn bool, name, target, taskType string, interval int) (uint, error) {
	db := dbcore.GetDBInstance()
	task := models.PingTask{
		Clients:   clients,
		DefaultOn: defaultOn,
		Name:      name,
		Target:    target,
		Type:      taskType,
		Interval:  interval,
	}
	if err := db.Create(&task).Error; err != nil {
		return 0, err
	}
	return task.Id, nil
}

// DeletePingTask deletes ping tasks by IDs.
func DeletePingTask(ids []uint) error {
	if len(ids) == 0 {
		return nil
	}
	db := dbcore.GetDBInstance()
	return db.Where("id IN ?", ids).Delete(&models.PingTask{}).Error
}

// EditPingTask updates ping tasks.
func EditPingTask(tasks []*models.PingTask) error {
	if len(tasks) == 0 {
		return nil
	}
	db := dbcore.GetDBInstance()
	for _, task := range tasks {
		if task == nil {
			continue
		}
		if err := db.Save(task).Error; err != nil {
			return err
		}
	}
	return nil
}

// GetAllPingTasks returns all ping tasks ordered by weight descending.
func GetAllPingTasks() ([]models.PingTask, error) {
	db := dbcore.GetDBInstance()
	var list []models.PingTask
	err := db.Order("weight desc, id asc").Find(&list).Error
	return list, err
}

// UpdatePingTaskOrder updates task ordering weights.
func UpdatePingTaskOrder(order map[uint]int) error {
	if len(order) == 0 {
		return nil
	}
	db := dbcore.GetDBInstance()
	for id, weight := range order {
		if err := db.Model(&models.PingTask{}).Where("id = ?", id).Update("weight", weight).Error; err != nil {
			return err
		}
	}
	return nil
}

// GetPingTasksByClient returns ping tasks assigned to a client (including default_on tasks).
func GetPingTasksByClient(uuid string) []models.PingTask {
	db := dbcore.GetDBInstance()
	var allClients []models.Client
	db.Select("uuid").Find(&allClients)
	allUUIDs := make([]string, 0, len(allClients))
	for _, c := range allClients {
		if c.UUID != "" {
			allUUIDs = append(allUUIDs, c.UUID)
		}
	}
	isDefaultOnClient := false
	for _, clientUUID := range allUUIDs {
		if clientUUID == uuid {
			isDefaultOnClient = true
			break
		}
	}
	var list []models.PingTask
	db.Order("weight desc, id asc").Find(&list)
	result := make([]models.PingTask, 0, len(list))
	for _, task := range list {
		if task.DefaultOn && isDefaultOnClient {
			result = append(result, task)
			continue
		}
		for _, clientUUID := range task.Clients {
			if clientUUID == uuid {
				result = append(result, task)
				break
			}
		}
	}
	return result
}

// AddDefaultOnClientUUID handles new client registration: apply default-on ping tasks.
func AddDefaultOnClientUUID(clientUUID string) error {
	db := dbcore.GetDBInstance()
	var tasks []models.PingTask
	if err := db.Where("default_on = ?", true).Find(&tasks).Error; err != nil {
		return err
	}
	if len(tasks) == 0 {
		return nil
	}
	for _, task := range tasks {
		updated := append(task.Clients, clientUUID)
		if err := db.Model(&models.PingTask{}).Where("id = ?", task.Id).Update("clients", updated).Error; err != nil {
			return err
		}
	}
	return nil
}

// SavePingRecord stores a single ping measurement result.
func SavePingRecord(record models.PingRecord) error {
	db := dbcore.GetDBInstance()
	return db.Create(&record).Error
}

// GetPingRecords returns ping records for a client, optionally filtered by task ID.
// Pass taskID < 0 to skip task filter.
func GetPingRecords(uuid string, taskID int, startTime, endTime time.Time) ([]models.PingRecord, error) {
	db := dbcore.GetDBInstance()
	query := db.Where("client = ?", uuid)
	if taskID >= 0 {
		query = query.Where("task_id = ?", taskID)
	} else {
		query = query.Where("task_id >= ?", 0)
	}
	if !startTime.IsZero() {
		query = query.Where("created_at >= ?", startTime)
	}
	if !endTime.IsZero() {
		query = query.Where("created_at <= ?", endTime)
	}
	var records []models.PingRecord
	if err := query.Order("created_at desc").Find(&records).Error; err != nil {
		return nil, err
	}
	return records, nil
}

// DeleteAllPingRecords removes all ping records.
func DeleteAllPingRecords() error {
	db := dbcore.GetDBInstance()
	return db.Where("1 = 1").Delete(&models.PingRecord{}).Error
}

// DeletePingRecordsBefore deletes ping records older than the given time.
func DeletePingRecordsBefore(t time.Time) {
	db := dbcore.GetDBInstance()
	db.Where("created_at < ?", t).Delete(&models.PingRecord{})
}

// SortClients sorts client UUIDs.
func SortClients(uuids []string) {
	sort.Strings(uuids)
}

// --- Legacy load notification scheduling helpers ---

// ReloadPingSchedule reloads the active ping schedule (called by server startup).
// This is declared here for package visibility; actual logic lives in utils/pingSchedule.
var ReloadPingSchedule = func([]models.PingTask) error {
	log.Println("ReloadPingSchedule not initialized")
	return nil
}

// ReloadLoadNotification reloads load notification schedules.
var ReloadLoadNotification = func() error {
	log.Println("ReloadLoadNotification not initialized")
	return nil
}

// ClearTaskResultsByTimeBefore is a no-op in the stripped-down version.
func ClearTaskResultsByTimeBefore(t time.Time) {
	// No-op: task execution removed in security-hardened version.
}

var _ = clause.OnConflict{} // ensure clause import is used
