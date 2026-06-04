#!/usr/bin/env python3

import json
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path("/Users/linshu/Downloads/AICoding/opentranstype")
SOURCE_XCLOC = ROOT / ".localizations" / "en.xcloc"
OUTPUT_ROOT = ROOT / ".localizations" / "generated"
NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
ET.register_namespace("", NS["x"])

LOCALES = ["zh-Hans", "ja", "fr", "es", "ko", "de", "ru", "th"]

ROWS = """
%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@	%1$@ → %2$@
Accessibility access granted	辅助功能权限已允许	アクセシビリティの許可が有効です	Accès Accessibilité autorisé	Acceso de Accesibilidad concedido	손쉬운 사용 권한이 허용되었습니다	Bedienungshilfen-Zugriff gewährt	Доступ к Универсальному доступу разрешён	อนุญาตการช่วยการเข้าถึงแล้ว
Accessibility access is required to read and replace text	需要允许辅助功能权限才能读取和替换文本	テキストの読み取りと置き換えにはアクセシビリティの許可が必要です	L’accès Accessibilité est nécessaire pour lire et remplacer le texte	Se requiere acceso de Accesibilidad para leer y reemplazar texto	텍스트를 읽고 바꾸려면 손쉬운 사용 권한이 필요합니다	Für das Lesen und Ersetzen von Text ist Bedienungshilfen-Zugriff erforderlich	Для чтения и замены текста требуется доступ к Универсальному доступу	ต้องเปิดสิทธิ์การช่วยการเข้าถึงเพื่ออ่านข้อความและแทนที่ข้อความ
Allow Accessibility access in System Settings	请在系统设置中允许辅助功能权限	システム設定でアクセシビリティの許可を有効にしてください	Autorisez l’accès Accessibilité dans Réglages Système	Permite el acceso de Accesibilidad en Configuración del Sistema	시스템 설정에서 손쉬운 사용 권한을 허용하세요	Erlaube den Bedienungshilfen-Zugriff in den Systemeinstellungen	Разрешите доступ к Универсальному доступу в Системных настройках	อนุญาตการเข้าถึงการช่วยการเข้าถึงในการตั้งค่าระบบ
Already in target language	已是目标语言	すでに対象言語です	Déjà dans la langue cible	Ya está en el idioma de destino	이미 대상 언어입니다	Bereits in der Zielsprache	Уже на целевом языке	เป็นภาษาปลายทางอยู่แล้ว
Asking the system to prepare the language pack	正在请求系统准备语言包	システムに言語パックの準備を依頼中	Demande au système de préparer le pack de langue	Pidiendo al sistema que prepare el paquete de idioma	시스템에 언어 팩 준비를 요청하는 중	System wird aufgefordert, das Sprachpaket vorzubereiten	Запрос системе на подготовку языкового пакета	กำลังขอให้ระบบเตรียมแพ็กภาษา
Automatically checks on-device translation language packs. The source language is detected from your input when translating.	自动检查本机翻译语言包状态。实际翻译时会根据输入内容自动识别源语言。	デバイス上の翻訳用言語パックを自動で確認します。翻訳時には入力内容から元の言語を自動判定します。	Vérifie automatiquement les packs de langue de traduction sur l’appareil. La langue source est détectée à partir de votre saisie lors de la traduction.	Comprueba automáticamente los paquetes de idioma de traducción del dispositivo. El idioma de origen se detecta a partir de tu entrada al traducir.	기기 내 번역 언어 팩 상태를 자동으로 확인합니다. 번역할 때는 입력 내용을 기준으로 원문 언어를 자동 감지합니다.	Prüft automatisch die auf dem Gerät verfügbaren Übersetzungssprachpakete. Die Ausgangssprache wird beim Übersetzen anhand deiner Eingabe erkannt.	Автоматически проверяет языковые пакеты перевода на устройстве. Исходный язык при переводе определяется по вашему вводу.	ตรวจสอบแพ็กภาษาสำหรับการแปลบนอุปกรณ์โดยอัตโนมัติ ภาษาต้นทางจะถูกตรวจจับจากข้อความที่คุณป้อนเมื่อทำการแปล
Available to download	可下载	ダウンロード可能	Disponible au téléchargement	Disponible para descargar	다운로드 가능	Zum Download verfügbar	Доступно для загрузки	พร้อมให้ดาวน์โหลด
Average length	平均长度	平均長さ	Longueur moyenne	Longitud media	평균 길이	Durchschnittslänge	Средняя длина	ความยาวเฉลี่ย
Check Again	重新检查	再確認	Vérifier à nouveau	Comprobar de nuevo	다시 확인	Erneut prüfen	Проверить снова	ตรวจสอบอีกครั้ง
Checking	检查中	確認中	Vérification...	Comprobando...	확인 중	Wird geprüft	Проверка...	กำลังตรวจสอบ
Checking language pack...	正在检查语言包...	言語パックを確認中...	Vérification du pack de langue...	Comprobando paquete de idioma...	언어 팩 확인 중...	Sprachpaket wird geprüft...	Проверка языкового пакета...	กำลังตรวจสอบแพ็กภาษา...
Checking sample pair: %1$@ → %2$@. When translating, the source language is detected automatically from your input.	检查示例语言对：%1$@ → %2$@。实际使用时会按输入内容自动识别源语言。	サンプル言語ペアを確認中: %1$@ → %2$@。実際の翻訳時には入力内容から元の言語を自動判定します。	Vérification de la paire d’exemple : %1$@ → %2$@. Lors de la traduction, la langue source est détectée automatiquement à partir de votre saisie.	Comprobando par de ejemplo: %1$@ → %2$@. Al traducir, el idioma de origen se detecta automáticamente a partir de tu entrada.	샘플 언어 쌍 확인 중: %1$@ → %2$@. 실제 번역 시에는 입력 내용을 기준으로 원문 언어를 자동 감지합니다.	Beispiel-Sprachpaar wird geprüft: %1$@ → %2$@. Beim Übersetzen wird die Ausgangssprache automatisch anhand deiner Eingabe erkannt.	Проверяется пример языковой пары: %1$@ → %2$@. При переводе исходный язык автоматически определяется по вашему вводу.	กำลังตรวจสอบคู่ภาษาตัวอย่าง: %1$@ → %2$@ เมื่อแปลจริง ระบบจะตรวจจับภาษาต้นทางจากข้อความที่คุณป้อนโดยอัตโนมัติ
Choose a target language	选择目标语言	対象言語を選択	Choisissez une langue cible	Elige un idioma de destino	대상 언어를 선택하세요	Wähle eine Zielsprache	Выберите целевой язык	เลือกภาษาปลายทาง
Choose target language	选择目标语言	対象言語を選択	Choisir la langue cible	Elegir idioma de destino	대상 언어 선택	Zielsprache auswählen	Выберите целевой язык	เลือกภาษาปลายทาง
Choose the language you translate into most often. The first time you use a language pair, Apple may ask you to download the on-device translation pack.	选择你最常翻译到的语言。首次使用对应语言对时，系统可能会提示下载 Apple 本机翻译语言包。	もっともよく翻訳先にする言語を選んでください。初めてその言語ペアを使う際、Apple からデバイス上の翻訳用言語パックのダウンロードを求められる場合があります。	Choisissez la langue vers laquelle vous traduisez le plus souvent. La première fois que vous utilisez une paire de langues, Apple peut vous demander de télécharger le pack de traduction sur l’appareil.	Elige el idioma al que traduces con más frecuencia. La primera vez que uses un par de idiomas, Apple puede pedirte que descargues el paquete de traducción del dispositivo.	가장 자주 번역하는 언어를 선택하세요. 해당 언어 쌍을 처음 사용할 때 Apple이 기기 내 번역 언어 팩 다운로드를 요청할 수 있습니다.	Wähle die Sprache, in die du am häufigsten übersetzt. Wenn du ein Sprachpaar zum ersten Mal verwendest, fordert Apple dich möglicherweise auf, das Übersetzungssprachpaket auf dem Gerät herunterzuladen.	Выберите язык, на который вы переводите чаще всего. При первом использовании языковой пары Apple может попросить вас загрузить языковой пакет перевода на устройство.	เลือกภาษาที่คุณแปลไปบ่อยที่สุด ครั้งแรกที่ใช้คู่ภาษานั้น Apple อาจขอให้คุณดาวน์โหลดแพ็กแปลภาษาบนอุปกรณ์
Clear	清空	消去	Effacer	Borrar	지우기	Löschen	Очистить	ล้าง
Close	关闭	閉じる	Fermer	Cerrar	닫기	Schließen	Закрыть	ปิด
Completed translations will appear here.	完成一次翻译后会显示在这里。	翻訳を完了するとここに表示されます。	Les traductions terminées apparaîtront ici.	Las traducciones completadas aparecerán aquí.	완료된 번역이 여기에 표시됩니다.	Abgeschlossene Übersetzungen werden hier angezeigt.	Завершённые переводы появятся здесь.	คำแปลที่เสร็จแล้วจะแสดงที่นี่
Current default: %@	当前默认：%@	現在のデフォルト: %@	Valeur actuelle par défaut : %@	Predeterminado actual: %@	현재 기본값: %@	Aktuelle Voreinstellung: %@	Текущее значение по умолчанию: %@	ค่าเริ่มต้นปัจจุบัน: %@
Current settings	当前设置	現在の設定	Réglages actuels	Configuración actual	현재 설정	Aktuelle Einstellungen	Текущие настройки	การตั้งค่าปัจจุบัน
Default target language	默认目标语言	デフォルトの対象言語	Langue cible par défaut	Idioma de destino predeterminado	기본 대상 언어	Standard-Zielsprache	Язык перевода по умолчанию	ภาษาปลายทางเริ่มต้น
Disable translation	禁用翻译	翻訳を無効にする	Désactiver la traduction	Desactivar traducción	번역 끄기	Übersetzung deaktivieren	Отключить перевод	ปิดการแปล
Download	下载	ダウンロード	Télécharger	Descargar	다운로드	Herunterladen	Скачать	ดาวน์โหลด
Download failed	下载失败	ダウンロードに失敗しました	Échec du téléchargement	La descarga falló	다운로드에 실패했습니다	Download fehlgeschlagen	Не удалось загрузить	ดาวน์โหลดไม่สำเร็จ
Download language pack	下载语言包	言語パックをダウンロード	Télécharger le pack de langue	Descargar paquete de idioma	언어 팩 다운로드	Sprachpaket herunterladen	Скачать языковой пакет	ดาวน์โหลดแพ็กภาษา
Downloading...	下载中...	ダウンロード中...	Téléchargement...	Descargando...	다운로드 중...	Wird heruntergeladen...	Загрузка...	กำลังดาวน์โหลด...
Drag to move toolbar	拖拽移动工具栏	ドラッグしてツールバーを移動	Faites glisser pour déplacer la barre d’outils	Arrastra para mover la barra de herramientas	드래그하여 도구 막대 이동	Ziehen, um die Werkzeugleiste zu verschieben	Перетащите, чтобы переместить панель	ลากเพื่อย้ายแถบเครื่องมือ
Drag to resize toolbar	拖拽调整工具栏大小	ドラッグしてツールバーのサイズを変更	Faites glisser pour redimensionner la barre d’outils	Arrastra para cambiar el tamaño de la barra de herramientas	드래그하여 도구 막대 크기 조절	Ziehen, um die Größe der Werkzeugleiste zu ändern	Перетащите, чтобы изменить размер панели	ลากเพื่อปรับขนาดแถบเครื่องมือ
Enable translation	启用翻译	翻訳を有効にする	Activer la traduction	Activar traducción	번역 켜기	Übersetzung aktivieren	Включить перевод	เปิดการแปล
English	英语	英語	Anglais	Inglés	영어	Englisch	Английский	อังกฤษ
Failed to prepare language pack: %@	语言包准备失败：%@	言語パックの準備に失敗しました: %@	Échec de la préparation du pack de langue : %@	No se pudo preparar el paquete de idioma: %@	언어 팩 준비에 실패했습니다: %@	Vorbereitung des Sprachpakets fehlgeschlagen: %@	Не удалось подготовить языковой пакет: %@	เตรียมแพ็กภาษาไม่สำเร็จ: %@
Get Started	开始使用	始める	Commencer	Empezar	시작하기	Loslegen	Начать	เริ่มใช้งาน
History	历史记录	履歴	Historique	Historial	기록	Verlauf	История	ประวัติ
Installed	已安装	インストール済み	Installé	Instalado	설치됨	Installiert	Установлено	ติดตั้งแล้ว
Keep typing	继续输入	入力を続けてください	Continuez à saisir	Sigue escribiendo	계속 입력하세요	Weiter tippen	Продолжайте ввод	พิมพ์ต่อไป
Language pack download cancelled	已取消语言包下载	言語パックのダウンロードをキャンセルしました	Téléchargement du pack de langue annulé	Descarga del paquete de idioma cancelada	언어 팩 다운로드가 취소되었습니다	Download des Sprachpakets abgebrochen	Загрузка языкового пакета отменена	ยกเลิกการดาวน์โหลดแพ็กภาษาแล้ว
Language pack installed. You're ready to go.	语言包已安装，可以开始使用	言語パックがインストールされました。使用を開始できます。	Le pack de langue est installé. Vous êtes prêt.	El paquete de idioma está instalado. Ya puedes empezar.	언어 팩이 설치되었습니다. 바로 사용할 수 있습니다.	Sprachpaket installiert. Du kannst loslegen.	Языковой пакет установлен. Всё готово.	ติดตั้งแพ็กภาษาแล้ว พร้อมใช้งาน
Language pack not ready	语言包未就绪	言語パックの準備ができていません	Le pack de langue n’est pas prêt	El paquete de idioma no está listo	언어 팩이 준비되지 않았습니다	Sprachpaket ist nicht bereit	Языковой пакет не готов	แพ็กภาษายังไม่พร้อม
Language packs	语言包	言語パック	Packs de langue	Paquetes de idioma	언어 팩	Sprachpakete	Языковые пакеты	แพ็กภาษา
Language pair not supported	不支持该语言对	この言語ペアはサポートされていません	Cette paire de langues n’est pas prise en charge	Este par de idiomas no es compatible	이 언어 쌍은 지원되지 않습니다	Dieses Sprachpaar wird nicht unterstützt	Эта языковая пара не поддерживается	ไม่รองรับคู่ภาษานี้
Listening for input	正在监听输入	入力を待機中	En attente de saisie	Escuchando la entrada	입력을 기다리는 중	Warte auf Eingabe	Ожидание ввода	กำลังรอการป้อนข้อความ
Listening status	监听状态	監視状態	État de l’écoute	Estado de escucha	감지 상태	Überwachungsstatus	Состояние прослушивания	สถานะการรับฟัง
Next	下一步	次へ	Suivant	Siguiente	다음	Weiter	Далее	ถัดไป
No error details were returned by the system	系统未返回可用错误信息	システムから利用可能なエラー情報が返されませんでした	Le système n’a renvoyé aucun détail d’erreur exploitable	El sistema no devolvió detalles de error utilizables	시스템이 사용할 수 있는 오류 정보를 반환하지 않았습니다	Das System hat keine verwendbaren Fehlermeldungen zurückgegeben	Система не вернула полезных сведений об ошибке	ระบบไม่ได้ส่งรายละเอียดข้อผิดพลาดที่ใช้งานได้กลับมา
No history yet	还没有历史记录	まだ履歴がありません	Aucun historique pour le moment	Aún no hay historial	아직 기록이 없습니다	Noch kein Verlauf	Истории пока нет	ยังไม่มีประวัติ
No text found	未读到文本	テキストが見つかりません	Aucun texte trouvé	No se encontró texto	텍스트를 찾을 수 없습니다	Kein Text gefunden	Текст не найден	ไม่พบข้อความ
Not checked	未检查	未確認	Non vérifié	Sin comprobar	확인되지 않음	Nicht geprüft	Не проверено	ยังไม่ได้ตรวจสอบ
Not selected	尚未选择	未選択	Non sélectionné	No seleccionado	선택되지 않음	Nicht ausgewählt	Не выбрано	ยังไม่ได้เลือก
Once the translation is ready, press ↓ or click the overlay button to replace the original text.	译文准备好后，按 ↓ 或点击浮窗按钮直接替换原文。	翻訳の準備ができたら、↓ を押すかオーバーレイのボタンをクリックして元の文を置き換えます。	Une fois la traduction prête, appuyez sur ↓ ou cliquez sur le bouton flottant pour remplacer le texte d’origine.	Cuando la traducción esté lista, pulsa ↓ o haz clic en el botón flotante para reemplazar el texto original.	번역이 준비되면 ↓ 키를 누르거나 오버레이 버튼을 눌러 원문을 바로 바꿀 수 있습니다.	Sobald die Übersetzung bereit ist, drücke ↓ oder klicke auf die Overlay-Schaltfläche, um den Originaltext zu ersetzen.	Когда перевод будет готов, нажмите ↓ или кнопку во всплывающем окне, чтобы заменить исходный текст.	เมื่อคำแปลพร้อมแล้ว ให้กด ↓ หรือคลิกปุ่มโอเวอร์เลย์เพื่อแทนที่ข้อความต้นฉบับ
Open Accessibility Settings	打开辅助功能设置	アクセシビリティ設定を開く	Ouvrir les réglages Accessibilité	Abrir ajustes de Accesibilidad	손쉬운 사용 설정 열기	Bedienungshilfen öffnen	Открыть настройки Универсального доступа	เปิดการตั้งค่าการช่วยการเข้าถึง
Open main window	打开主窗口	メインウインドウを開く	Ouvrir la fenêtre principale	Abrir la ventana principal	메인 창 열기	Hauptfenster öffnen	Открыть главное окно	เปิดหน้าต่างหลัก
OpenTransType	OpenTransType	OpenTransType	OpenTransType	OpenTransType	OpenTransType	OpenTransType	OpenTransType	OpenTransType
Paused	已暂停	一時停止中	En pause	En pausa	일시 중지됨	Pausiert	Приостановлено	หยุดชั่วคราว
Preparing download	准备下载	ダウンロードを準備中	Préparation du téléchargement	Preparando descarga	다운로드 준비 중	Download wird vorbereitet	Подготовка загрузки	กำลังเตรียมดาวน์โหลด
Preparing...	准备中...	準備中...	Préparation...	Preparando...	준비 중...	Vorbereitung...	Подготовка...	กำลังเตรียม...
Press ↓ to replace text	按 ↓ 覆盖原文	↓ を押して元の文を置き換え	Appuyez sur ↓ pour remplacer le texte	Pulsa ↓ para reemplazar el texto	↓ 키를 눌러 원문 교체	Drücke ↓, um den Text zu ersetzen	Нажмите ↓, чтобы заменить текст	กด ↓ เพื่อแทนที่ข้อความเดิม
Quit	退出	終了	Quitter	Salir	종료	Beenden	Выход	ออก
Read current input	读取当前输入	現在の入力を読み取る	Lire la saisie actuelle	Leer la entrada actual	현재 입력 읽기	Aktuelle Eingabe lesen	Считать текущий ввод	อ่านข้อความที่ป้อนอยู่
Reading input...	读取输入中...	入力を読み取り中...	Lecture de la saisie...	Leyendo entrada...	입력을 읽는 중...	Lese Eingabe...	Чтение ввода...	กำลังอ่านข้อความที่ป้อน...
Ready	已准备好	準備完了	Prêt	Listo	준비 완료	Bereit	Готово	พร้อม
Recent target language	最近目标语言	最近の対象言語	Dernière langue cible	Idioma de destino reciente	최근 대상 언어	Letzte Zielsprache	Последний целевой язык	ภาษาปลายทางล่าสุด
Replace failed	替换失败	置き換えに失敗しました	Échec du remplacement	No se pudo reemplazar	교체에 실패했습니다	Ersetzen fehlgeschlagen	Не удалось заменить	แทนที่ไม่สำเร็จ
Replace original text	覆盖原文	元のテキストを置き換え	Remplacer le texte d’origine	Reemplazar el texto original	원문 교체	Originaltext ersetzen	Заменить исходный текст	แทนที่ข้อความต้นฉบับ
Right-click inside any app text field to translate as you type. Pick a target language, keep typing, then press ↓ to replace the original text with the translation.	在任意 App 的文本框中右键，开启边写边译。选择目标语言后继续输入，按 ↓ 用译文覆盖原文。	どのアプリのテキスト入力欄でも右クリックすると、入力しながら翻訳できます。対象言語を選び、そのまま入力を続けて、↓ を押すと翻訳で元の文を置き換えます。	Faites un clic droit dans le champ de texte de n’importe quelle app pour traduire au fil de la saisie. Choisissez une langue cible, continuez à taper, puis appuyez sur ↓ pour remplacer le texte d’origine par la traduction.	Haz clic derecho dentro de cualquier campo de texto de una app para traducir mientras escribes. Elige un idioma de destino, sigue escribiendo y luego pulsa ↓ para reemplazar el texto original con la traducción.	어느 앱의 텍스트 입력란에서든 오른쪽 클릭해 입력과 동시에 번역할 수 있습니다. 대상 언어를 고르고 계속 입력한 다음 ↓ 키를 눌러 원문을 번역문으로 바꾸세요.	Klicke in einem Textfeld einer beliebigen App mit der rechten Maustaste, um beim Tippen zu übersetzen. Wähle eine Zielsprache, tippe weiter und drücke dann ↓, um den Originaltext durch die Übersetzung zu ersetzen.	Щёлкните правой кнопкой мыши в текстовом поле любого приложения, чтобы переводить по мере ввода. Выберите целевой язык, продолжайте печатать, затем нажмите ↓, чтобы заменить исходный текст переводом.	คลิกขวาในช่องข้อความของแอปใดก็ได้เพื่อแปลขณะพิมพ์ เลือกภาษาปลายทาง พิมพ์ต่อ แล้วกด ↓ เพื่อแทนที่ข้อความต้นฉบับด้วยคำแปล
Search	搜索	検索	Rechercher	Buscar	검색	Suchen	Поиск	ค้นหา
Settings	设置	設定	Réglages	Ajustes	설정	Einstellungen	Настройки	การตั้งค่า
Show translation overlay	显示翻译浮窗	翻訳オーバーレイを表示	Afficher la fenêtre flottante de traduction	Mostrar la superposición de traducción	번역 오버레이 표시	Übersetzungs-Overlay anzeigen	Показать окно перевода	แสดงโอเวอร์เลย์การแปล
Simplified Chinese	简体中文	簡体字中国語	Chinois simplifié	Chino simplificado	중국어 간체	Vereinfachtes Chinesisch	Китайский (упрощённый)	จีนตัวย่อ
Source characters	原文字数	原文文字数	Caractères source	Caracteres de origen	원문 글자 수	Zeichen im Original	Символы исходного текста	จำนวนอักขระต้นฉบับ
Start typing to translate	输入内容后自动翻译	入力すると自動で翻訳します	Commencez à saisir pour traduire	Empieza a escribir para traducir	입력하면 자동으로 번역됩니다	Mit dem Tippen beginnen, um zu übersetzen	Начните вводить текст для перевода	เริ่มพิมพ์เพื่อแปล
Stats	数据统计	統計	Statistiques	Estadísticas	통계	Statistiken	Статистика	สถิติ
Target language	目标语言	対象言語	Langue cible	Idioma de destino	대상 언어	Zielsprache	Целевой язык	ภาษาปลายทาง
Text too long	文本过长	テキストが長すぎます	Texte trop long	El texto es demasiado largo	텍스트가 너무 깁니다	Text ist zu lang	Текст слишком длинный	ข้อความยาวเกินไป
This language pack is not installed yet. Download it first.	这个语言包还没安装，请先下载	この言語パックはまだインストールされていません。先にダウンロードしてください。	Ce pack de langue n’est pas encore installé. Téléchargez-le d’abord.	Este paquete de idioma aún no está instalado. Descárgalo primero.	이 언어 팩은 아직 설치되지 않았습니다. 먼저 다운로드하세요.	Dieses Sprachpaket ist noch nicht installiert. Lade es zuerst herunter.	Этот языковой пакет ещё не установлен. Сначала загрузите его.	แพ็กภาษานี้ยังไม่ได้ติดตั้ง โปรดดาวน์โหลดก่อน
This sample language pair is not supported by the system	系统暂不支持这个示例语言对	このサンプル言語ペアはシステムでサポートされていません	Cette paire de langues d’exemple n’est pas prise en charge par le système	Este par de idiomas de ejemplo no es compatible con el sistema	이 샘플 언어 쌍은 시스템에서 지원되지 않습니다	Dieses Beispiel-Sprachpaar wird vom System nicht unterstützt	Эта примерная языковая пара не поддерживается системой	ระบบไม่รองรับคู่ภาษาตัวอย่างนี้
Translated characters	译文字数	翻訳文字数	Caractères traduits	Caracteres traducidos	번역문 글자 수	Zeichen in der Übersetzung	Символы перевода	จำนวนอักขระคำแปล
Translating...	翻译中...	翻訳中...	Traduction...	Traduciendo...	번역 중...	Übersetze...	Перевод...	กำลังแปล...
Translation disabled	翻译已禁用	翻訳は無効です	Traduction désactivée	Traducción desactivada	번역이 꺼짐	Übersetzung deaktiviert	Перевод отключён	ปิดการแปลแล้ว
Translation enabled	翻译已启用	翻訳は有効です	Traduction activée	Traducción activada	번역이 켜짐	Übersetzung aktiviert	Перевод включён	เปิดการแปลแล้ว
Translation failed. Try again later	翻译失败，稍后重试	翻訳に失敗しました。後でもう一度お試しください	Échec de la traduction. Réessayez plus tard	La traducción falló. Inténtalo de nuevo más tarde	번역에 실패했습니다. 나중에 다시 시도하세요	Übersetzung fehlgeschlagen. Bitte später erneut versuchen	Не удалось перевести. Повторите попытку позже	แปลไม่สำเร็จ โปรดลองอีกครั้งภายหลัง
Translation timed out	翻译超时	翻訳がタイムアウトしました	Délai de traduction dépassé	Tiempo de espera de traducción agotado	번역 시간이 초과되었습니다	Zeitüberschreitung bei der Übersetzung	Время ожидания перевода истекло	การแปลหมดเวลา
Translation unavailable right now	暂时无法翻译	現在は翻訳できません	Traduction momentanément indisponible	La traducción no está disponible ahora mismo	지금은 번역할 수 없습니다	Übersetzung derzeit nicht verfügbar	Перевод сейчас недоступен	ไม่สามารถแปลได้ในขณะนี้
Translations	翻译次数	翻訳回数	Traductions	Traducciones	번역 횟수	Übersetzungen	Переводы	จำนวนการแปล
Type in any app text field and see the translation instantly.	在任意 App 的输入框里输入文字，并自动显示译文。	どのアプリの入力欄でも文字を入力すると、すぐに翻訳が表示されます。	Saisissez du texte dans le champ de n’importe quelle app et voyez la traduction s’afficher instantanément.	Escribe en cualquier campo de texto de una app y verás la traducción al instante.	어느 앱의 입력란에서든 글자를输入하면 번역이 즉시 표시됩니다.	Tippe in ein Textfeld einer beliebigen App und sieh die Übersetzung sofort.	Вводите текст в поле любого приложения и сразу увидите перевод.	พิมพ์ในช่องข้อความของแอปใดก็ได้ แล้วดูคำแปลได้ทันที
Unsupported	不支持	未対応	Non pris en charge	No compatible	지원되지 않음	Nicht unterstützt	Не поддерживается	ไม่รองรับ
Waiting for input	等待输入	入力待ち	En attente de saisie	Esperando entrada	입력을 기다리는 중	Warte auf Eingabe	Ожидание ввода	กำลังรอการป้อนข้อความ
Welcome	欢迎使用	ようこそ	Bienvenue	Bienvenido	환영합니다	Willkommen	Добро пожаловать	ยินดีต้อนรับ
""".strip()


def build_translations():
    translations = {}
    for line in ROWS.splitlines():
        parts = line.split("\t")
        if len(parts) != 9:
            raise ValueError(f"Expected 9 columns, got {len(parts)}: {line}")
        source = parts[0]
        translations[source] = dict(zip(LOCALES, parts[1:]))
    return translations


def localized_contents_dir(xcloc_dir: Path) -> Path:
    return xcloc_dir / "Localized Contents"


def rewrite_xliff(locale: str, translations: dict[str, dict[str, str]]):
    target_xcloc = OUTPUT_ROOT / f"{locale}.xcloc"
    if target_xcloc.exists():
        shutil.rmtree(target_xcloc)
    shutil.copytree(SOURCE_XCLOC, target_xcloc)

    contents_path = target_xcloc / "contents.json"
    contents = json.loads(contents_path.read_text())
    contents["targetLocale"] = locale
    contents_path.write_text(json.dumps(contents, ensure_ascii=False, indent=2) + "\n")

    loc_dir = localized_contents_dir(target_xcloc)
    source_xliff = loc_dir / "en.xliff"
    target_xliff = loc_dir / f"{locale}.xliff"
    if target_xliff.exists():
        target_xliff.unlink()
    source_xliff.rename(target_xliff)

    tree = ET.parse(target_xliff)
    root = tree.getroot()
    for file_node in root.findall("x:file", NS):
        file_node.set("target-language", locale)
        for unit in file_node.findall(".//x:trans-unit", NS):
            source_node = unit.find("x:source", NS)
            target_node = unit.find("x:target", NS)
            if source_node is None or target_node is None:
                continue
            source = source_node.text or ""
            if source not in translations:
                target_node.text = source
                target_node.set("state", "translated")
                continue
            target_node.text = translations[source][locale]
            target_node.set("state", "translated")

    tree.write(target_xliff, encoding="utf-8", xml_declaration=True)
    return target_xcloc


def main():
    if not SOURCE_XCLOC.exists():
        raise FileNotFoundError(f"Missing source xcloc: {SOURCE_XCLOC}")

    translations = build_translations()
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

    generated = []
    for locale in LOCALES:
        generated.append(rewrite_xliff(locale, translations))

    for path in generated:
        print(path)


if __name__ == "__main__":
    main()
