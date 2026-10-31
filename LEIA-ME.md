# Sistema da Brennu’s: passo a passo

O que você tem nesta pasta:

| Arquivo | Para que serve |
|---|---|
| `index.html` | O site que o cliente usa para agendar (sem precisar de WhatsApp) |
| `painel.html` | O painel com login: cada barbeiro vê os seus agendamentos, o dono vê todos |
| `config.js` | Onde você cola os dados do banco de dados |
| `schema.sql` | Cria o banco de dados (tabelas, regras e os serviços e barbeiros) |
| `manifest*.webmanifest`, `sw.js`, `icon-*.png` | Fazem o site e o painel serem **instalados no celular como aplicativo**, com o ícone da Brennu’s |

O site precisa de um **banco de dados online** e de uma **hospedagem sua**. Os dois têm plano gratuito.

## 1. Criar o banco de dados (Supabase)

1. Crie uma conta grátis em **supabase.com** e clique em **New project**. Escolha a região mais perto (São Paulo) e anote a senha do banco.
2. No menu da esquerda abra **SQL Editor** → **New query**, cole **todo** o conteúdo do `schema.sql` e clique em **Run**. Deve aparecer "Success".
3. Vá em **Project Settings → API Keys** (ou no botão **Connect**) e copie:
   - a **Project URL** (algo como `https://xxxx.supabase.co`)
   - a chave **publishable** (começa com `sb_publishable_`). Se o seu projeto só mostrar a chave antiga **anon**, ela também serve.
4. Abra o `config.js` e cole os dois valores no lugar dos textos `COLE_AQUI...`.

**Nunca** cole a chave `secret` ou `service_role` no `config.js`.

## 2. Criar os logins

1. No Supabase abra **Authentication → Users → Add user → Create new user**. Crie um usuário para o **dono** e um para **cada barbeiro**, com e-mail e senha. Marque **Auto Confirm User**.
2. Volte ao **SQL Editor** e libere cada um. Troque os e-mails pelos reais:

```sql
-- dono: vê todos os agendamentos
insert into profiles (user_id, role, barber_id)
select id, 'owner', null from auth.users where email = 'dono@exemplo.com';

-- um barbeiro: vê só os dele (repita trocando e-mail e nome)
insert into profiles (user_id, role, barber_id)
select u.id, 'barber', b.id from auth.users u, barbers b
where u.email = 'breno@exemplo.com' and b.name = 'Breno';
```

Os nomes dos barbeiros são: `Breno`, `João Paulo`, `LK`, `Alison Silva`.

## 3. Colocar no ar

Suba **todos os arquivos desta pasta, menos o `schema.sql` e este `LEIA-ME.md`**, juntos na mesma hospedagem em uma hospedagem gratuita, por exemplo:

- **Netlify**: em app.netlify.com/drop, arraste a pasta inteira.
- **Cloudflare Pages**, **Vercel** ou **GitHub Pages** também funcionam.

O site fica no endereço que a hospedagem der, e o painel em `…/painel.html`.

## 4. Testar antes de entregar

1. Abra o site, faça um agendamento e veja a tela "Horário confirmado!".
2. Abra o painel, entre como dono e confira se o agendamento aparece.
3. Entre como o barbeiro escolhido e confira se aparece só para ele.
4. Tente agendar o mesmo horário de novo: ele deve sumir da lista.

## Aplicativo com a cara da Brennu’s

Com a hospedagem no ar (endereço `https://`), o cliente abre o site no celular e escolhe **"Adicionar à tela inicial"** (iPhone: botão de compartilhar → "Adicionar à Tela de Início"; Android: menu do navegador → "Instalar aplicativo"). Fica um ícone da Brennu’s, que abre em tela cheia, sem barra do navegador. O painel dos barbeiros e do dono também pode ser instalado do mesmo jeito. Isso **não é um aplicativo de loja** (App Store e Google Play); publicar nas lojas é outro trabalho, com conta de desenvolvedor paga.

## O que o sistema faz

- O cliente escolhe serviço, barbeiro, dia e horário e **não precisa de cadastro**.
- Horários já ocupados **somem** para os outros clientes. O banco **nunca aceita dois agendamentos no mesmo horário** para o mesmo barbeiro. Se alguém reservar no mesmo segundo, o segundo recebe o aviso para escolher outro.
- "Sem preferência" escolhe um barbeiro livre automaticamente.
- **Comanda**: em cada agendamento o barbeiro ou o dono adiciona **serviços extras** e **produtos**. Produto vendido sai do **estoque** automaticamente, e o sistema recusa se acabou. Ao concluir, escolhem a **forma de pagamento** (Pix, dinheiro, crédito ou débito).
- **Novo agendamento pelo painel**: para o cliente que chegou na hora ou ligou. O banco também não deixa marcar dois no mesmo horário.
- **Lembrar cliente**: botão que abre o WhatsApp do cliente com a mensagem de lembrete pronta (você só aperta enviar).
- **Aba Produtos** (só o dono): estoque, entrada de mercadoria e cadastro de produto novo.
- Aba **Resumo**, com **fechamento da semana** (segunda a sábado, atual e passada) e os últimos 30 ou 90 dias: faturamento, atendimentos, ticket médio, % de cancelamentos, faturamento por dia, **melhores e piores dias da semana**, faturamento por barbeiro, serviços e produtos mais vendidos e formas de pagamento. O dono vê tudo e filtra por barbeiro. Cada barbeiro vê só os números dele.
- Atendimento de segunda a sábado, das 9h às 20h (horário de Bahia).

## Limites que você precisa saber

- No plano grátis do Supabase, o projeto **pausa depois de cerca de uma semana sem uso**. Para uma barbearia que atende todo dia isso não deve acontecer, mas confira as regras atuais do plano. O plano pago evita a pausa.
- **Não inclui ainda**: lembrete automático para o cliente, cadastro de serviços e preços pelo painel (por enquanto edite em **Table Editor → services**; o estoque e os produtos o dono ajusta direto no painel), cartão fidelidade, pacotes, gestão das assinaturas do clube, lembrete **automático** (hoje o lembrete é um botão que você aperta), pagamento online e proteção contra agendamentos falsos em massa.
- Este material **não foi testado com um Supabase real**: só conferi a sintaxe dos arquivos e a lógica dos horários. Na primeira vez pode aparecer algum erro pequeno. Se aparecer, copie a mensagem e peça o ajuste.


## Produtos já cadastrados

O `schema.sql` cadastra 6 produtos com os nomes e preços que apareceram na página do AppBarber (Balm, Buxa, Gel cola, Home aromatico, Homem helo, Maquina acabamento) e **estoque zero**. Confira os nomes e preços e ajuste o estoque na aba Produtos antes de usar.


## Se algo não funcionar

Abra o site, aperte **F12** (computador) e olhe a aba **Console**: a mensagem de erro aparece em vermelho. As mais comuns:

| O que acontece | O que fazer |
|---|---|
| O site abre o WhatsApp em vez de gravar o agendamento | O `config.js` não foi preenchido, ou não foi enviado junto com o `index.html` na hospedagem. |
| Lista de serviços ou horários não carrega, erro `permission denied` | O `schema.sql` não rodou até o fim. Projetos novos do Supabase só liberam tabelas com `GRANT` explícito, e o arquivo já tem isso. Se a primeira execução parou no meio, o mais simples é **criar um projeto novo** no Supabase e rodar o arquivo inteiro de novo. |
| Erro `Could not find the function public.book` | O mesmo caso acima: o `schema.sql` parou antes de criar as funções. |
| Painel mostra "Aguardando liberação" | Falta o passo 2.2 (o `insert into profiles` do e-mail daquela pessoa). |
| "E-mail ou senha incorretos" | Confira se o usuário foi criado com **Auto Confirm User** marcado. |
| O horário aparece livre mas dá "acabou de ser ocupado" | Normal: alguém reservou no mesmo instante. O site atualiza a lista. |

**Conferir se o banco ficou certo**, no SQL Editor:

```sql
select count(*) from barbers;    -- deve dar 4
select count(*) from services;   -- deve dar 15
select count(*) from products;   -- deve dar 6
```

**Conferir os agendamentos depois de hospedar:** faça um agendamento de teste no site, abra **Table Editor → appointments** no Supabase e veja a linha criada. Depois entre no painel e confira se ele aparece lá.
