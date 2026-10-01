<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="Ícone do app SnakeStick: uma mulher meio serpente oferecendo uma maçã vermelha">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>Crie um pendrive de instalação do Windows 10 / 11 no seu Mac.</b><br>
  Escolha uma ISO, escolha um pendrive e clique em Iniciar. Sem Terminal, sem Boot Camp, sem dividir o <code>install.wim</code>.
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="Baixe a versão mais recente" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 26.6 ou posterior" src="https://img.shields.io/badge/macOS-26.6%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10 e 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="Licença: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <b>Português (Brasil)</b> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick copiando uma ISO do Windows 11 para um pendrive USB, etapa 6 de 8">
</p>

---

## ✨ Por que usar o SnakeStick

- 🪟 **Basta o app.** Escolha uma ISO do Windows 10 ou 11 (ou solte-a na janela), escolha um pendrive USB e clique em
  **Iniciar Gravação**.
- 📦 **Arquivos de instalação grandes não são problema.** As ISOs recentes do Windows trazem um `install.wim` com mais de
  4 GB, que não cabe em um pendrive FAT32. O SnakeStick coloca o Windows em uma partição NTFS e adiciona uma pequena
  partição de inicialização com o carregador [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs), o mesmo layout que o
  [Rufus](https://rufus.ie) usa. Nada é dividido.
- 🔐 **Funciona com o Secure Boot.** O carregador de inicialização incluído é assinado pela Microsoft. Para PCs que
  revogaram o certificado de 2011 da Microsoft, o SnakeStick pode usar os carregadores de inicialização assinados com
  Windows UEFI CA 2023 das ISOs do Windows 11 25H2 ou posterior.
- ✅ **Confere o próprio trabalho.** Após a gravação, ele lê o pendrive inteiro de novo e o compara com a ISO, arquivo por
  arquivo.
- 🛡️ **Fica longe dos discos do seu Mac.** Somente discos externos e removíveis aparecem na lista. Os discos internos e o
  disco de inicialização nunca aparecem, o destino é verificado novamente logo antes da gravação, e nada é apagado até
  que você confirme.
- 🧹 **Nenhum resto do Mac.** A partição do Windows é gravada sem nunca ser montada, então nenhum arquivo `.DS_Store`, `._`
  ou `.fseventsd` vai parar no pendrive.
- 🍎 **Um app nativo para Mac.** Escrito em Swift e SwiftUI, disponível em inglês, coreano, japonês, chinês (simplificado
  e tradicional), alemão, francês, espanhol, português (Brasil) e russo. Gratuito e de código aberto, sob a GPLv3.

## 📥 Download

Baixe a versão mais recente na aba **[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** e mova o
**SnakeStick** para a pasta **Aplicativos**. O app é assinado e autenticado pela Apple.

## 🧰 O que você precisa

| | |
|---|---|
| **Mac** | macOS Tahoe 26.6 ou posterior e uma senha de administrador |
| **ISO do Windows** | Uma ISO de instalação do Windows 10 ou 11, por exemplo da página de download do [Windows 11](https://www.microsoft.com/pt-br/software-download/windows11) ou do [Windows 10](https://www.microsoft.com/pt-br/software-download/windows10) da Microsoft |
| **Pendrive USB** | Grande o suficiente para a ISO; pendrives pequenos demais aparecem esmaecidos. 16 GB é um tamanho seguro para as ISOs atuais do Windows 11. |
| **PC de destino** | Um PC que inicialize no modo UEFI. A inicialização pelo BIOS legado (CSM) não é suportada. |

> [!CAUTION]
> A gravação **apaga tudo** no pendrive USB selecionado. Antes, copie dele tudo o que você quiser manter.

## 🔑 Primeira execução: duas permissões concedidas uma única vez

O SnakeStick grava o pendrive por meio de uma pequena ferramenta auxiliar que é executada em segundo plano com privilégios
de administrador, para que o próprio app nunca precise ser executado como root. O macOS pede que você aprove essa
ferramenta auxiliar uma vez:

1. **Permita a ferramenta auxiliar.** Na primeira vez que você clicar em **Iniciar Gravação**, o macOS pedirá que você
   permita a ferramenta auxiliar do SnakeStick. Ative o **SnakeStick** em **Ajustes do Sistema › Geral › Itens de Início
   de Sessão e Extensões** e tente novamente.
2. **Conceda o Acesso Total ao Disco.** O macOS impede que ferramentas auxiliares em segundo plano acessem discos
   removíveis e pastas como **Downloads**, a menos que o app tenha Acesso Total ao Disco. Adicione o **SnakeStick** em
   **Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco**. O SnakeStick avisa quando essa permissão
   está faltando e tem um botão que abre a página certa.

Depois disso, o SnakeStick pede a sua senha de administrador uma vez a cada gravação de um pendrive.

## 🚀 Criando um pendrive

1. **Escolha a ISO.** Clique em **Escolher…** em **ISO de Origem** ou solte a ISO na janela. O SnakeStick mostra a versão
   do Windows, a arquitetura e o tamanho.
2. **Escolha o pendrive.** Conecte-o e selecione-o em **Disco de Destino**.
3. **Confira as opções.**
   - **Nome do Volume**: o nome do pendrive. Por padrão, é o próprio nome da ISO.
   - **Verificar após gravar**: ativado por padrão. Acrescenta alguns minutos, e vale a pena.
   - **Usar carregadores de inicialização assinados com Windows UEFI CA 2023**: necessário apenas para PCs que revogaram
     o certificado de Secure Boot de 2011 da Microsoft, e disponível apenas com ISOs do Windows 11 25H2 ou posterior. Se
     você não tiver certeza, deixe desativado.
4. Clique em **Iniciar Gravação**, confirme com **Apagar e Gravar** e digite a sua senha de administrador.
5. **Aguarde.** A barra de progresso mostra a etapa atual (8 no total) e o tempo restante. No pendrive USB 3 que testamos,
   uma ISO do Windows 11 de 8,7 GB levou cerca de 16 minutos, incluindo a verificação.
6. Quando o SnakeStick disser que terminou, clique em **Ejetar** para ejetar o pendrive.

Você pode clicar em **Parar** a qualquer momento. O pendrive fica impossibilitado de inicializar, e gravá-lo de novo
recomeça tudo do início.

## 💻 Inicializando o PC pelo pendrive

1. Conecte o pendrive ao PC e ligue-o mantendo pressionada a tecla do menu de inicialização. Geralmente é **F12**,
   **F11**, **F8** ou **Esc**; consulte o manual do seu PC.
2. Escolha a opção **UEFI** do pendrive USB.
3. A Instalação do Windows é iniciada.

Se o PC se recusar a inicializar pelo pendrive com o Secure Boot ativado, procure nas configurações do firmware uma opção
como **"Allow Microsoft 3rd Party UEFI CA"** e ative-a. Alguns PCs, em especial os Secured-core PCs, vêm com ela
desativada, e o carregador de inicialização UEFI:NTFS precisa dela. Desativar o Secure Boot durante a instalação também
funciona; ative-o de novo depois.

## ❓ Perguntas frequentes

<details>
<summary><b>Por que ele precisa de Acesso Total ao Disco?</b></summary>
<br>

A parte do SnakeStick que grava o pendrive é uma ferramenta auxiliar em segundo plano (um daemon do launchd). O macOS não
permite que ferramentas auxiliares desse tipo abram discos removíveis, ou leiam uma ISO em pastas como Downloads, a menos
que o app ao qual pertencem tenha Acesso Total ao Disco, e não existe uma permissão mais restrita que uma ferramenta
auxiliar possa pedir. Você concede a permissão ao app SnakeStick, e ela vale também para a ferramenta auxiliar dentro do
app.

</details>

<details>
<summary><b>Por que não simplesmente formatar o pendrive em FAT32, como fazia o Assistente do Boot Camp?</b></summary>
<br>

O FAT32 não comporta arquivos de 4 GB ou mais, e o `sources/install.wim` das ISOs atuais do Windows geralmente é maior
do que isso. A solução de contorno comum é dividir o arquivo. O SnakeStick, em vez disso, mantém o arquivo inteiro em uma
partição NTFS, e uma pequena partição FAT ao lado dela guarda o carregador UEFI:NTFS, que ensina o firmware do PC a ler
NTFS.

</details>

<details>
<summary><b>Ele consegue ignorar os requisitos de TPM ou de Secure Boot do Windows 11?</b></summary>
<br>

Não. O SnakeStick copia a ISO como ela é. Ele não contorna os requisitos de hardware, não adiciona arquivos de resposta
para instalações autônomas nem injeta drivers.

</details>

<details>
<summary><b>O que acontece se eu remover o pendrive ou parar no meio?</b></summary>
<br>

O SnakeStick faz a limpeza por conta própria, e o pendrive fica impossibilitado de inicializar. Grave-o de novo e tudo
ficará bem. Os discos do seu Mac nunca são tocados.

</details>

<details>
<summary><b>Posso criar uma imagem de disco em vez de gravar em um pendrive?</b></summary>
<br>

Pelo app, não. O SnakeStick grava somente em pendrives USB.

</details>

> [!NOTE]
> O SnakeStick é um projeto novo. Pendrives criados com ele já inicializaram a Instalação do Windows em um PC x64 com o
> Secure Boot ativado, mas uma instalação completa do Windows a partir de um deles ainda não foi testada. Se algo der
> errado, [abra um issue](https://github.com/team-unstablers/SnakeStick/issues) e anexe o registro (**Mostrar Registro…**
> no app).

## 🙏 Feito com

O SnakeStick não existiria sem estes softwares livres. Obrigado!

- [ntfs-3g](https://github.com/tuxera/ntfs-3g): cria e grava a partição NTFS
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs): o carregador de inicialização que permite ao firmware UEFI iniciar o Windows a partir do NTFS
- [wimlib](https://github.com/ebiggers/wimlib): lê a imagem de inicialização do Windows
- [Rufus](https://github.com/pbatard/rufus): seu código-fonte foi usado como referência

O SnakeStick foi escrito por um agente de programação baseado em LLM, sob supervisão humana.

## 🐍 Sobre o ícone

A serpente do Éden, oferecendo uma maçã ao seu Mac. A maçã está inteira: ninguém deu uma mordida ainda.

## 🛠️ Para desenvolvedores

Como o SnakeStick funciona, como compilá-lo a partir do código-fonte e como executar os testes: veja
[docs/DESIGN.md](docs/DESIGN.md) (em inglês).

## 📄 Licença

O SnakeStick é software livre sob a [GNU General Public License v3.0 ou posterior](COPYING). Ele é fornecido sem nenhuma
garantia. Os componentes incluídos mantêm as próprias licenças; veja [docs/DESIGN.md](docs/DESIGN.md#license).
