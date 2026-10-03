# Fox_Theater

Sistema de **teatro e cinema sincronizado para RedM**, com apresentações, projeções e bilheteria.

## 🎭 Funcionalidades

- Shows e filmes sincronizados para jogadores próximos.
- Teatro de Saint Denis e cinemas configurados em Saint Denis, Valentine e Blackwater.
- Bilheteria com preço configurável.
- Compatível com **VORP, RSG e standalone**.
- Comandos administrativos `/theater` e `/theaterstop`.
- Blips e prompts configuráveis.

## 🎟️ Sistema de ingresso

Nos frameworks VORP/RSG, comprar na bilheteria entrega o item `theatreticket`.

O ingresso guarda em **metadata o teatro/cinema onde foi comprado**. Depois, o jogador usa o item naquele local; o ingresso é consumido e uma apresentação aleatória começa para o público próximo.

No modo standalone, sem inventário, a compra inicia a apresentação diretamente.

### RSG - item em `rsg-core/shared/items.lua`

```lua
['theatreticket'] = {
    name = 'theatreticket',
    label = 'Ingresso de Teatro',
    weight = 0,
    type = 'item',
    image = 'theatreticket.png',
    unique = true,
    useable = true,
    shouldClose = true,
    description = 'Ingresso para uma apresentação.'
},
```

### VORP

Cadastre `theatreticket` na tabela/cache de itens do `vorp_inventory`. O recurso registra o item utilizável automaticamente.

## 🛠️ Instalação

1. Coloque `Fox_Theater` em `resources`.
2. Adicione `ensure Fox_Theater` no `server.cfg`.
3. Configure `shared/config.lua`.
4. Se usar VORP/RSG, cadastre o item `theatreticket` no inventário.

## ⚙️ Configuração principal

```lua
Config.Price = 5
Config.Framework = 'auto' -- auto / vorp / rsg / standalone
Config.Ticket.Item = 'theatreticket'
Config.EnableBlips = true
```

## ✍️ Créditos

Desenvolvido e adaptado por **SR.IGAMER TV | FOX**.

<br>

**MINHA LOJA:**
<div>
  <a href="https://discord.gg/ySk8WVzY5n" target="_blank"><img src="https://img.shields.io/badge/Discord-7289DA?style=for-the-badge&logo=discord&logoColor=white" target="_blank"></a>
</div>

<br>

**Siga-nos:**
<div>
  <a href="https://www.youtube.com/@SRIGAMERTV" target="_blank"><img src="https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white" target="_blank"></a>
  <a href="https://www.instagram.com/sr.igamer_tv" target="_blank"><img src="https://img.shields.io/badge/-Instagram-%23E4405F?style=for-the-badge&logo=instagram&logoColor=white" target="_blank"></a>
  <a href="https://discord.gg/kh2KTGvaVX" target="_blank"><img src="https://img.shields.io/badge/Discord-7289DA?style=for-the-badge&logo=discord&logoColor=white" target="_blank"></a>
</div>

<br>

**Entrar-contato:**
<div>
  <a href="mailto:kelvinsom22kb@gmail.com"><img src="https://img.shields.io/badge/-Gmail-%23333?style=for-the-badge&logo=gmail&logoColor=white" target="_blank"></a>
</div>


## 🛡️ Licença

Distribuído sob a licença MIT. Consulte `LICENSE`.
