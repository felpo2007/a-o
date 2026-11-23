--!strict
-- Códigos de resgate (D-207; prompt de interface §9: "Trate código válido, inválido, expirado e já
-- utilizado. O servidor confirma o benefício."). Puro: o servidor (CampanhaService, op
-- "code_redeem") valida e entrega; o cliente (ShopController, aba CÓDIGOS) só mostra.
-- Cada código vale uma vez por conta: fica gravado em campaign.owned["codigo:<CÓDIGO>"] (o mapa de
-- posse da campanha, que é união entre servidores).
-- A lista é do dono: o de lançamento foi aprovado por ele em 2026-11-20 (DESIGN D-207).
local Codigos = {}

export type Codigo = {
	codigo: string, -- em caixa alta, só letras e números
	cr: number, -- créditos de intendência
	estrelas: number, -- estrelas do passe de campanha
	de: number, -- vale a partir de (os.time, UTC)
	ate: number, -- vale até (os.time, UTC)
}

Codigos.LISTA = {
	-- lançamento: 250 CI (pouco mais que uma semana de recompensa diária, que dá 30 a 90 por dia)
	{ codigo = "STARLITE1965", cr = 250, estrelas = 0, de = 0, ate = 1801439999 }, -- até 31/01/2027
} :: { Codigo }

Codigos.MAX = 24 -- tamanho máximo do que o jogador digita
Codigos.TENTATIVAS = 8 -- erros por minuto antes de esperar (contra tentar todos os códigos)

-- o que o jogador digitou -> o código limpo (caixa alta, sem espaço nem traço); nil se não serve
function Codigos.limpar(texto: any): string?
	if type(texto) ~= "string" then
		return nil
	end
	local s = string.upper((string.gsub(texto, "[%s%-_]", "")))
	if #s == 0 or #s > Codigos.MAX or string.find(s, "[^%w]") then
		return nil
	end
	return s
end

function Codigos.chave(codigo: string): string
	return "codigo:" .. codigo
end

-- Resultado: ok e o código, ou o motivo ("invalido", "vencido", "ainda_nao", "usado")
function Codigos.validar(texto: any, agora: number, usados: { [string]: boolean }): (boolean, string, Codigo?)
	local c = Codigos.limpar(texto)
	if not c then
		return false, "invalido", nil
	end
	for _, d in Codigos.LISTA do
		if d.codigo == c then
			if usados[Codigos.chave(c)] then
				return false, "usado", d
			elseif agora < d.de then
				return false, "ainda_nao", d
			elseif agora > d.ate then
				return false, "vencido", d
			end
			return true, "ok", d
		end
	end
	return false, "invalido", nil
end

-- texto para o jogador (o servidor manda; o cliente mostra)
Codigos.MENSAGEM = {
	invalido = "Este código não existe.",
	vencido = "Este código venceu.",
	ainda_nao = "Este código ainda não vale.",
	usado = "Você já usou este código.",
	espera = "Muitas tentativas: espere um minuto.",
	perfil = "Seu perfil ainda está carregando.",
} :: { [string]: string }

return Codigos
