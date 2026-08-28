package model

// DimensionKey 是 Slowlight 固定的长期观察坐标，不是用户可编辑标签。
type DimensionKey string

const (
	DimensionBody         DimensionKey = "body"
	DimensionCognition    DimensionKey = "cognition"
	DimensionOutput       DimensionKey = "output"
	DimensionRelationship DimensionKey = "relationship"
)

type DimensionDefinition struct {
	Key   DimensionKey `json:"key"`
	Name  string       `json:"name"`
	Icon  string       `json:"icon"`
	Color string       `json:"color"`
}

var Dimensions = []DimensionDefinition{
	{Key: DimensionBody, Name: "身体", Icon: "💪", Color: "#52c41a"},
	{Key: DimensionCognition, Name: "认知", Icon: "🧠", Color: "#1890ff"},
	{Key: DimensionOutput, Name: "产出", Icon: "🎯", Color: "#722ed1"},
	{Key: DimensionRelationship, Name: "关系", Icon: "❤️", Color: "#eb2f96"},
}

func LegacyDimensionKey(name string) DimensionKey {
	for _, item := range Dimensions {
		if item.Name == name {
			return item.Key
		}
	}
	return ""
}

func IsValidDimensionKey(key DimensionKey) bool {
	if key == "" {
		return true
	}
	for _, item := range Dimensions {
		if item.Key == key {
			return true
		}
	}
	return false
}
