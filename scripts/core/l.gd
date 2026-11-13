class_name L
extends RefCounted
## Textos da interface (i18n). Toda frase que o jogador lê sai de i18n/strings.csv por chave:
##   L.t("MENU_PLAY")                          -> "JOGAR"
##   L.t("HUD_RESPAWN", {s = 7})               -> "VOLTA EM 7s"   (no CSV: "VOLTA EM {s}s")
## Um valor de parâmetro que começa com "@" é outra chave, traduzida também:
##   L.t("TOAST_ORDER", {p = 1, order = "@ORDER_ATACAR"})
## Chave sem tradução volta como a própria chave (fácil de ver na tela e o teste de cobertura acusa).
## Em rede, os avisos viajam como [chave, valores] e cada máquina traduz no próprio idioma (L.tp).


static func t(key: String, params: Dictionary = {}) -> String:
	var s := String(TranslationServer.translate(key))
	if params.is_empty():
		return s
	var p := {}
	for k in params:
		var v = params[k]
		if v is String and String(v).begins_with("@"):
			v = String(TranslationServer.translate(String(v).substr(1)))
		elif v is float and is_equal_approx(v, roundf(v)):
			v = int(v) # números inteiros que passaram por JSON (rede) voltam sem ".0"
		p[k] = v
	return s.format(p)


## Traduz um par [chave, valores] (formato usado nos eventos e snapshots de rede).
static func tp(parts) -> String:
	if parts is Array and parts.size() >= 1:
		var params: Dictionary = parts[1] if parts.size() > 1 and parts[1] is Dictionary else {}
		return t(String(parts[0]), params)
	return str(parts)
