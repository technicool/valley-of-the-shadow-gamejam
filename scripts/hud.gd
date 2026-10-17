extends CanvasLayer
## Gameplay HUD: health meter top-left, pickup scripture and suggestion top-center.
## Health is read from PlayerStats; the banner is driven by show_message().

const MESSAGE_HOLD_SECONDS := 4.0
const MESSAGE_FADE_SECONDS := 0.6

@onready var _health_meter: ProgressBar = $Root/HealthMeter
@onready var _banner: PanelContainer = $Root/Banner
@onready var _quote: Label = $Root/Banner/Lines/Quote
@onready var _reference: Label = $Root/Banner/Lines/Reference
@onready var _suggestion: Label = $Root/Banner/Lines/Suggestion

var _banner_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	_banner.hide()
	PlayerStats.health_changed.connect(_on_health_changed)
	_on_health_changed(PlayerStats.health, PlayerStats.max_health)


func _on_health_changed(health: int, max_health: int) -> void:
	_health_meter.max_value = max_health
	_health_meter.value = health


## Shows a pickup's scripture and suggestion at top-center, then fades it out.
func show_message(quote: String, reference: String, suggestion: String) -> void:
	_quote.text = quote
	_reference.text = reference
	_suggestion.text = suggestion
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner.show()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(MESSAGE_HOLD_SECONDS)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, MESSAGE_FADE_SECONDS)
	_banner_tween.tween_callback(_banner.hide)
