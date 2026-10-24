extends RefCounted
## Thought tiers: size, color, phrases and scoring. Tier 0 is the smallest worry.

const MAX_TIER := 10

const RADII := [26.0, 34.0, 44.0, 56.0, 68.0, 82.0, 98.0, 116.0, 136.0, 158.0, 182.0]

const COLORS := [
	Color("9ad1d4"), Color("a0c4ff"), Color("bdb2ff"), Color("ffc6ff"), Color("ffadad"),
	Color("ffd6a5"), Color("fdffb6"), Color("caffbf"), Color("ff8fab"), Color("c77dff"),
	Color("ff6b6b"),
]

const PHRASES := [
	["хм", "ой", "а?", "м-м", "ну…"],
	["утюг?", "дверь?", "а вдруг", "зачем?", "кстати…"],
	["забыл ответить", "завтра рано", "что за звук?", "а дедлайн?"],
	["я выключил газ?", "письмо без ответа", "прочитал и молчит", "а если заболею"],
	["кринж из 2009", "надо было ответить иначе", "дедлайн в понедельник", "я сказал «ты тоже»"],
	["что он имел в виду?", "меня все обсуждают", "а если уволят", "я всё забыл"],
	["я всё делаю не так", "все успешнее меня", "мне 30, а я…", "это навсегда"],
	["почему я такой?", "я упускаю жизнь", "а если я злодей в чьей-то истории"],
	["смысл жизни", "кем я стану в 50", "а что, если всё зря"],
	["ВСЁ ПРОПАЛО", "КОНЕЦ СВЕТА", "Я НЕ СПЛЮ УЖЕ ЧАС"],
	["ЭКЗИСТЕНЦИАЛЬНЫЙ УЖАС", "ВСЕЛЕННАЯ РАСШИРЯЕТСЯ"],
]

## Relative chance of each tier appearing as the next thought to drop.
const SPAWN_WEIGHTS := [30.0, 26.0, 22.0, 14.0, 8.0]

## Sleep minutes at which a toast appears. 240 (07:00) is the alarm.
const MILESTONES := {
	20: "Кажется, засыпаю…",
	60: "Целый час сна!",
	120: "Снится, что опоздал на экзамен",
	180: "Глубокий сон. Почти.",
	300: "Проспал работу? Да и ладно",
	480: "Легенда сна: 8 часов",
}

const WAKE_LINES := [
	"Опять эти мысли.",
	"Может, просто встать и попить воды?",
	"Мозг: «Давай вспомним всё, что ты сделал не так»",
	"Классика. Сна ни в одном глазу.",
	"Овцы закончились на 347-й.",
	"Попробуй дышать раньше.",
]


## Sleep minutes for creating a thought of this tier.
static func points_for(tier: int) -> int:
	return maxi(1, tier - 1)


static func random_phrase(tier: int) -> String:
	return PHRASES[tier].pick_random()


static func ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
