# 📚 THOTH - Study Helper

> **Estude com inteligência. Alcance seus objetivos.**

Uma app multiplataforma de estudo com autenticação Google, timers, notificações inteligentes e sincronização em tempo real com Firebase.

---

## 🌐 Plataformas Suportadas

| Plataforma | Status | Download |
|-----------|--------|----------|
| 📱 **Android** | ✅ Disponível | [Google Play Store](#) |
| 📱 **iOS** | ✅ Disponível | [App Store](#) |
| 🌐 **Web** | ✅ Disponível | [thoth.web.app](https://thoth.web.app) |
| 💻 **Windows** | ✅ Disponível | [GitHub Releases](https://github.com/seu-usuario/THOTH/releases) |
| 💻 **macOS** | ✅ Disponível | [GitHub Releases](https://github.com/seu-usuario/THOTH/releases) |
| 💻 **Linux** | ✅ Disponível | [GitHub Releases](https://github.com/seu-usuario/THOTH/releases) |

---

## 🎯 Funcionalidades

- ✨ **Google Sign In** - Login seguro com sua conta Google
- 📚 **Gestão de Sessões de Estudo** - Organize seus objetivos
- ⏱️ **Timers com Notificações** - Lembretes inteligentes
- 📊 **Análise de Progresso** - Acompanhe seu avanço
- 🔔 **Notificações Personalizadas** - Lembretes em tempo real
- 💬 **Partilha de Dicas** - Partilhe com amigos
- 🔄 **Sincronização em Nuvem** - Mesma conta em todas as plataformas
- 🌙 **Dark Mode** - Modo escuro para noite

---

## 🚀 Como Usar

### **Windows**
1. Descarregue o ficheiro `.exe` em [Releases](https://github.com/seu-usuario/THOTH/releases)
2. Execute o ficheiro
3. Nenhuma instalação necessária!

### **macOS**
1. Descarregue o ficheiro `.app.zip` em [Releases](https://github.com/seu-usuario/THOTH/releases)
2. Descompacte o ficheiro
3. Arraste para a pasta `Aplicações`

### **Linux**
1. Descarregue o ficheiro `.AppImage` em [Releases](https://github.com/seu-usuario/THOTH/releases)
2. Dê permissão de execução: `chmod +x thoth-linux.AppImage`
3. Clique duas vezes para executar

### **Web**
Aceda a [thoth.web.app](https://thoth.web.app) no seu navegador.

### **Android/iOS**
Descarregue da Play Store ou App Store.

---

## 💻 Requisitos do Sistema

### **Windows**
- Windows 10 ou superior
- 100MB de espaço em disco

### **macOS**
- macOS 10.14 ou superior
- 150MB de espaço em disco

### **Linux**
- Ubuntu 18.04+ ou equivalente
- 100MB de espaço em disco

### **Web**
- Qualquer navegador moderno
- JavaScript ativado

---

## 🛠️ Desenvolvimento

### **Pré-requisitos**
- Flutter 3.24+
- Dart 3.3+
- Git

### **Setup Local**

```bash
# Clone o repositório
git clone https://github.com/seu-usuario/THOTH.git
cd THOTH

# Instale dependências
flutter pub get

# Configure Firebase (automático)
flutterfire configure --project=thoth-a5c7a

# Execute a app
flutter run
```

### **Compilar para Release**

```bash
# Windows
flutter build windows --release
# Resultado: build/windows/runner/Release/thoth_final_final.exe

# macOS
flutter build macos --release
# Resultado: build/macos/Build/Products/Release/thoth_final_final.app

# Linux
flutter build linux --release
# Resultado: build/linux/x64/release/bundle/

# Web
flutter build web --release
firebase deploy --only hosting
```

### **Publicar Novo Release**

```bash
# 1. Atualizar versão no pubspec.yaml
# 2. Compilar para todas as plataformas (acima)
# 3. Fazer commit
git add .
git commit -m "Release v1.0.1"

# 4. Criar tag
git tag v1.0.1

# 5. Push (GitHub Actions compila automaticamente!)
git push origin main --tags

# 6. Fazer upload manual ou aguardar CI/CD
```

---

## 📁 Estrutura do Projeto

```
THOTH/
├── lib/                    # Código Dart
│   ├── main.dart          # Entrada principal
│   ├── screens/           # Telas da app
│   ├── models/            # Modelos de dados
│   ├── services/          # Serviços (Firebase, etc.)
│   └── widgets/           # Widgets reutilizáveis
├── android/               # Config Android
├── ios/                   # Config iOS
├── web/                   # Config Web
├── windows/               # Config Windows
├── macos/                 # Config macOS
├── linux/                 # Config Linux
├── pubspec.yaml           # Dependências
├── firebase.json          # Config Firebase
├── .firebaserc            # Config Firebase CLI
└── README.md              # Este ficheiro
```

---

## 🔐 Segurança & Privacidade

- ✅ **Autenticação Segura** - Firebase Authentication
- ✅ **Dados Encriptados** - HTTPS + Firestore
- ✅ **Sem Rastreamento** - Não partilhamos dados
- ✅ **Conformidade GDPR** - Direito a apagar/exportar dados

---

## 🐛 Relatar Problemas

Encontrou um bug? Abra uma [Issue](https://github.com/seu-usuario/THOTH/issues).

Inclua:
- Descrição clara
- Passos para reproduzir
- Versão do THOTH
- SO e versão

---

## 🤝 Contribuir

Quer ajudar? Faça um Fork, crie uma branch, e abra um Pull Request!

```bash
git checkout -b feature/sua-funcionalidade
git commit -m "Add: sua funcionalidade"
git push origin feature/sua-funcionalidade
```

---

## 📄 Licença

THOTH está sob a licença [MIT License](LICENSE).

---

## 📞 Contacto

- **Email:** contato@thoth.app
- **GitHub:** [@seu-usuario](https://github.com/seu-usuario)

---

## 🙏 Agradecimentos

Obrigado a:
- Flutter & Firebase pelos excelentes frameworks
- Contributors por melhorias
- Comunidade pelo feedback

---

**Estude com THOTH! 📚✨**

[⬆ Voltar ao topo](#-thoth---study-helper)
