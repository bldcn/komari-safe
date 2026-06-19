package models

// PingTask represents a monitoring ping configuration
type PingTask struct {
	Id        uint        `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	Clients   StringArray `json:"clients" gorm:"column:clients;type:text"`
	DefaultOn bool        `json:"default_on" gorm:"column:default_on;default:false"`
	Name      string      `json:"name" gorm:"column:name;type:varchar(100)"`
	Target    string      `json:"target" gorm:"column:target;type:varchar(255)"`
	Type      string      `json:"type" gorm:"column:type;type:varchar(20)"`
	Interval  int         `json:"interval" gorm:"column:interval;type:int"`
	Weight    int         `json:"weight" gorm:"column:weight;type:int;default:0"`
}

func (PingTask) TableName() string { return "ping_tasks" }

// PingRecord stores individual ping test results
type PingRecord struct {
	Id     uint      `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	TaskId uint      `json:"task_id" gorm:"column:task_id;type:int;index"`
	Client string    `json:"client" gorm:"column:client;type:varchar(36);index"`
	Value  int       `json:"value" gorm:"column:value;type:int"`
	Time   LocalTime `json:"time" gorm:"column:time;type:timestamp"`
}

func (PingRecord) TableName() string { return "ping_records" }
