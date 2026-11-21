import 'package:flutter/widgets.dart';

/// Translates user-facing labels for the languages currently supported by
/// the application.
String appText(BuildContext context, String english) {
  if (Localizations.localeOf(context).languageCode != 'ar') {
    return english;
  }

  const heardPrefix = 'Heard "';
  const heardSuffix = '", but a cell is being edited, so it was not inserted.';
  if (english.startsWith(heardPrefix) && english.endsWith(heardSuffix)) {
    final heard = english.substring(
      heardPrefix.length,
      english.length - heardSuffix.length,
    );
    return 'تم التعرّف على "$heard"، لكن هناك خلية قيد التحرير، لذلك لم يُدرج النص.';
  }

  return _arabic[english] ?? english;
}

const Map<String, String> _arabic = {
  'Settings': 'الإعدادات',
  'Done': 'تم',
  'Sheet': 'ورقة العمل',
  'Right-to-left': 'من اليمين إلى اليسار',
  'Mirrors column order and row numbers to the right edge for this sheet.':
      'يعكس ترتيب الأعمدة وأرقام الصفوف إلى الجانب الأيمن لهذه الورقة.',
  'Text': 'النص',
  'Default font': 'الخط الافتراضي',
  'App default': 'افتراضي التطبيق',
  'Default font for this sheet': 'الخط الافتراضي لهذه الورقة',
  'Reset to app default': 'إعادة إلى افتراضي التطبيق',
  'Customize...': 'تخصيص...',
  'Sample text   نص تجريبي   123': 'نص تجريبي   123',
  'Appearance': 'المظهر',
  'Grid line color': 'لون خطوط الشبكة',
  'Default': 'افتراضي',
  'Change...': 'تغيير...',
  'Alternating row colors': 'ألوان الصفوف المتناوبة',
  'Shade every other row': 'تظليل كل صف بالتناوب',
  'Stripe color': 'لون التظليل',
  'Grid line and stripe colors are saved in the file but only shown in Excelence, not in Excel. Cell fills are real Excel fills.':
      'تُحفظ ألوان خطوط الشبكة والتظليل في الملف وتظهر في Excelence فقط، وليس في Excel. أما تعبئة الخلايا فتُحفظ في Excel.',
  'Behavior': 'السلوك',
  'Search for a new row after adding it': 'البحث عن الصف الجديد بعد إضافته',
  'After adding a row from the status bar, filter the sheet by the value you typed so the new row is easy to find and fill in.':
      'بعد إضافة صف من شريط الحالة، تُصفّى الورقة حسب القيمة التي أدخلتها لتسهيل العثور على الصف الجديد وتعبئته.',
  'Language': 'اللغة',
  'General': 'عام',
  'Interface language': 'لغة الواجهة',
  'English': 'الإنجليزية',
  'Arabic': 'العربية',
  'Speech recognition': 'التعرّف على الكلام',
  'Speech language': 'لغة الكلام',
  'Arabic is the default speech language. The offline small model is about 460 MB and may run slower on CPU. It downloads on first use; audio stays on this device.':
      'العربية هي لغة الكلام الافتراضية. حجم النموذج المحلي الصغير نحو 460 ميغابايت وقد يكون أبطأ على المعالج. يُنزّل عند الاستخدام الأول، ويبقى الصوت على هذا الجهاز.',
  'Use system language': 'استخدام لغة النظام',
  'Arabic (Saudi Arabia)': 'العربية (السعودية)',
  'Open...': 'فتح...',
  'Rename...': 'إعادة تسمية...',
  'Save as...': 'حفظ باسم...',
  'Import...': 'استيراد...',
  'Download as...': 'تنزيل باسم...',
  'Print...': 'طباعة...',
  'Find and replace...': 'بحث واستبدال...',
  'Select all': 'تحديد الكل',
  'Clear formatting': 'مسح التنسيق',
  'Freeze rows and columns': 'تجميد الصفوف والأعمدة',
  'Show gridlines': 'إظهار خطوط الشبكة',
  'Zoom...': 'تكبير/تصغير...',
  'Full screen': 'ملء الشاشة',
  'Chart': 'مخطط',
  'Image': 'صورة',
  'Link': 'رابط',
  'Comment': 'تعليق',
  'Sort range...': 'فرز النطاق...',
  'Create a filter': 'إنشاء عامل تصفية',
  'Data validation...': 'التحقق من صحة البيانات...',
  'Remove duplicates': 'إزالة التكرارات',
  'Spell check': 'التدقيق الإملائي',
  'Keyboard shortcuts': 'اختصارات لوحة المفاتيح',
  'About Excelence': 'حول Excelence',
  'Bold (Ctrl+B)': 'عريض (Ctrl+B)',
  'Italic (Ctrl+I)': 'مائل (Ctrl+I)',
  'Underline (Ctrl+U)': 'تسطير (Ctrl+U)',
  'Strikethrough': 'يتوسطه خط',
  'Text color': 'لون النص',
  'Fill color': 'لون التعبئة',
  'Horizontal alignment': 'المحاذاة الأفقية',
  'Vertical alignment': 'المحاذاة العمودية',
  'Align left': 'محاذاة لليسار',
  'Align center': 'توسيط أفقي',
  'Align right': 'محاذاة لليمين',
  'Align top': 'محاذاة للأعلى',
  'Align middle': 'توسيط عمودي',
  'Align bottom': 'محاذاة للأسفل',
  'Reset alignment': 'إعادة تعيين المحاذاة',
  'Font...': 'الخط...',
  'Font for selected cells': 'خط الخلايا المحددة',
  'Reset to sheet default': 'إعادة إلى الخط الافتراضي للورقة',
  'Automatic': 'تلقائي',
  'Sheet default': 'افتراضي الورقة',
  'Add sheet': 'إضافة ورقة',
  'Rename sheet': 'إعادة تسمية الورقة',
  'Delete sheet': 'حذف الورقة',
  'Saved.': 'تم الحفظ.',
  'Saved a copy as ': 'تم حفظ نسخة باسم ',
  'Renamed to ': 'تمت إعادة التسمية إلى ',
  'Deleted ': 'تم حذف ',
  'Retry': 'إعادة المحاولة',
  'Save as': 'حفظ باسم',
  'Rename document': 'إعادة تسمية المستند',
  'Could not save your changes': 'تعذّر حفظ التغييرات',
  'The document is still open. You can try saving again, or close it anyway and lose the changes that were not saved.':
      'لا يزال المستند مفتوحًا. يمكنك محاولة الحفظ مرة أخرى أو إغلاقه رغم ذلك وفقدان التغييرات التي لم تُحفظ.',
  'Cancel': 'إلغاء',
  'Close anyway': 'إغلاق على أي حال',
  'This permanently deletes the file from the server. It cannot be undone.':
      'سيؤدي هذا إلى حذف الملف نهائيًا من الخادم. لا يمكن التراجع عن ذلك.',
  'Could not delete the document': 'تعذّر حذف المستند',
  'OK': 'موافق',
  'Name': 'الاسم',
  '.xlsx is added automatically': 'ستتم إضافة ‎.xlsx تلقائيًا',
  'Working...': 'جارٍ التنفيذ...',
  'No fill': 'بلا تعبئة',
  'Could not read the selected file.': 'تعذّرت قراءة الملف المحدد.',
  'Upload failed: ': 'فشل التحميل: ',
  'Use 6 hex digits, e.g. FFCC00': 'استخدم 6 خانات ست عشرية، مثل FFCC00',
  'Hex color': 'لون سداسي عشري',
  'Open spreadsheet': 'فتح جدول بيانات',
  'New spreadsheet': 'جدول بيانات جديد',
  'Upload from this device': 'تحميل من هذا الجهاز',
  'Up one level': 'مجلد واحد للأعلى',
  'Documents': 'المستندات',
  'Failed to load this folder: ': 'تعذّر تحميل هذا المجلد: ',
  'This folder is empty.': 'هذا المجلد فارغ.',
  'Filename': 'اسم الملف',
  'e.g. budget.xlsx': 'مثال: budget.xlsx',
  'Create': 'إنشاء',
  'Apply': 'تطبيق',
  'Font': 'الخط',
  'Size': 'الحجم',
  'Fill': 'التعبئة',
  'Preview': 'معاينة',
  'Bold': 'عريض',
  'Italic': 'مائل',
  'Underline': 'تسطير',
  'Add row below': 'إضافة صف أدناه',
  'Delete row': 'حذف الصف',
  'Row height...': 'ارتفاع الصف...',
  'Row height': 'ارتفاع الصف',
  'Height (pixels)': 'الارتفاع (بالبكسل)',
  'Enter a height from 16 to 500.': 'أدخل ارتفاعًا بين 16 و500.',
  'Invalid row height.': 'ارتفاع الصف غير صالح.',
  'Sort ascending': 'ترتيب تصاعدي',
  'Sort descending': 'ترتيب تنازلي',
  'Rename column': 'إعادة تسمية العمود',
  'Delete column': 'حذف العمود',
  'Sort': 'فرز',
  'Failed to delete row: ': 'تعذّر حذف الصف: ',
  'Failed to rename column: ': 'تعذّرت إعادة تسمية العمود: ',
  'Failed to delete column: ': 'تعذّر حذف العمود: ',
  'Failed to sort: ': 'تعذّر الفرز: ',
  'Failed to switch sheet: ': 'تعذّر التبديل إلى الورقة: ',
  'Failed to add sheet: ': 'تعذّرت إضافة الورقة: ',
  'Failed to delete sheet: ': 'تعذّر حذف الورقة: ',
  'Failed to rename sheet: ': 'تعذّرت إعادة تسمية الورقة: ',
  'Search this sheet…': 'البحث في هذه الورقة…',
  'Clear search': 'مسح البحث',
  'Search failed: ': 'فشل البحث: ',
  'No document open': 'لا يوجد مستند مفتوح',
  'New...': 'جديد...',
  'Try again': 'أعد المحاولة',
  'Saving...': 'جارٍ الحفظ...',
  'Unsaved changes': 'تغييرات غير محفوظة',
  'All changes saved': 'تم حفظ جميع التغييرات',
  'Add row with value...': 'إضافة صف بالقيمة...',
  'Live updates on': 'التحديثات المباشرة مفعّلة',
  'The server stopped live updates for this window. Open the document again to resume.':
      'أوقف الخادم التحديثات المباشرة لهذه النافذة. افتح المستند مجددًا لاستئنافها.',
  'Not connected to the server. Trying again...':
      'غير متصل بالخادم. جارٍ إعادة المحاولة...',
  'Live updates off': 'التحديثات المباشرة متوقفة',
  'Connecting...': 'جارٍ الاتصال...',
  'Reconnecting...': 'جارٍ إعادة الاتصال...',
  'Speech to text is not available on this device.':
      'تحويل الكلام إلى نص غير متاح على هذا الجهاز.',
  'Open a document first.': 'افتح مستندًا أولًا.',
  'I didn’t hear anything. Try again.': 'لم أسمع شيئًا. حاول مرة أخرى.',
  "I didn't hear anything. Try again.": 'لم أسمع شيئًا. حاول مرة أخرى.',
  'The offline speech model could not be downloaded or loaded. Check your internet connection on first use and available disk space, then try again.':
      'تعذّر تنزيل نموذج التعرّف المحلي على الكلام أو تحميله. تحقق من اتصال الإنترنت عند الاستخدام الأول ومن مساحة القرص المتاحة، ثم حاول مرة أخرى.',
  'Could not transcribe the audio. Try again.':
      'تعذّر تحويل الصوت إلى نص. حاول مرة أخرى.',
  'Speech settings are still loading. Please try again in a moment.':
      'لا تزال إعدادات الكلام قيد التحميل. حاول مرة أخرى بعد لحظات.',
  'Speech to text could not start. Check that a microphone is connected and that speech recognition is allowed in your system settings.':
      'تعذّر بدء تحويل الكلام إلى نص. تحقق من توصيل الميكروفون والسماح بالتعرّف على الكلام في إعدادات النظام.',
  'Microphone access is blocked. Allow it in your system settings, then try again.':
      'تم حظر الوصول إلى الميكروفون. اسمح به في إعدادات النظام ثم حاول مرة أخرى.',
  'Speech to text stopped unexpectedly. Try again.':
      'توقف تحويل الكلام إلى نص بشكل غير متوقع. حاول مرة أخرى.',
  'The text is in the cell. Press Enter to keep it, or Esc to discard it.':
      'أُدرج النص في الخلية. اضغط Enter للاحتفاظ به أو Esc لإلغائه.',
  'Finish editing the cell first (Enter or Esc), then start speech to text. To dictate while typing in a cell, use Windows voice typing (Win+H).':
      'أنهِ تحرير الخلية أولًا (Enter أو Esc)، ثم ابدأ تحويل الكلام إلى نص. للإملاء أثناء الكتابة في خلية، استخدم الإملاء الصوتي في Windows (Win+H).',
  "Can't reach the server. Check the connection and try again.":
      'تعذّر الاتصال بالخادم. تحقق من الاتصال وحاول مرة أخرى.',
  'Could not save the document. Check that the server is running and try again.':
      'تعذّر حفظ المستند. تحقق من تشغيل الخادم ثم حاول مرة أخرى.',
  'Could not create the document. Check that the server is running and try again.':
      'تعذّر إنشاء المستند. تحقق من تشغيل الخادم ثم حاول مرة أخرى.',
  'Could not open the document. Check that the server is running and try again.':
      'تعذّر فتح المستند. تحقق من تشغيل الخادم ثم حاول مرة أخرى.',
  'Listening... say what the cell should contain. Press Ctrl+Shift+M to stop.':
      'جارٍ الاستماع... قل ما تريد إدخاله في الخلية. اضغط Ctrl+Shift+M للإيقاف.',
  'Preparing offline speech recognition. First use downloads a roughly 460 MB model; audio stays on this device.':
      'جارٍ إعداد التعرّف المحلي على الكلام. يُنزّل نموذج بحجم 460 ميغابايت تقريبًا عند الاستخدام الأول، ويبقى الصوت على هذا الجهاز.',
  'Listening... say what to search for. Press Ctrl+Shift+M to stop.':
      'جارٍ الاستماع... قل ما تريد البحث عنه. اضغط Ctrl+Shift+M للإيقاف.',
  'Search by voice': 'البحث بالصوت',
  'Stop voice search': 'إيقاف البحث الصوتي',
  'File': 'ملف',
  'Edit': 'تحرير',
  'View': 'عرض',
  'Insert': 'إدراج',
  'Data': 'بيانات',
  'Tools': 'أدوات',
  'Help': 'مساعدة',
  'New': 'جديد',
  'Open': 'فتح',
  'Save': 'حفظ',
  'Rename': 'إعادة تسمية',
  'Close': 'إغلاق',
  'Delete': 'حذف',
  'Speech to text (Ctrl+Shift+M)': 'تحويل الكلام إلى نص (Ctrl+Shift+M)',
  'Stop speech to text (Ctrl+Shift+M)':
      'إيقاف تحويل الكلام إلى نص (Ctrl+Shift+M)',
  'Search': 'بحث',
  'Search...': 'بحث...',
  'Could not open a document. Check that the server is running and that this device can reach it.':
      'تعذّر فتح مستند. تحقق من تشغيل الخادم وإمكانية الوصول إليه من هذا الجهاز.',
  'Connect':
      'اتصال',
  'Connection':
      'الاتصال',
  'Server':
      'الخادم',
  'Server address':
      'عنوان الخادم',
  'Access token (if the server has one)':
      'رمز الوصول (إن كان للخادم رمز)',
  'Test connection':
      'اختبار الاتصال',
  'Save anyway':
      'حفظ على أي حال',
  'Show':
      'إظهار',
  'Hide':
      'إخفاء',
  'Change server address':
      'تغيير عنوان الخادم',
  'Connect to your Excelence server':
      'الاتصال بخادم Excelence',
  'Enter the network address of the PC that runs the server. It is kept on this device; you can change it later in Settings.':
      'أدخل عنوان الشبكة للكمبيوتر الذي يشغّل الخادم. يُحفظ على هذا الجهاز ويمكنك تغييره لاحقًا من الإعدادات.',
  'The server shows its address and token with: excelence-server config show':
      'يعرض الخادم عنوانه والرمز عبر الأمر: excelence-server config show',
  'Enter the server address.':
      'أدخل عنوان الخادم.',
  'That is not a valid address. Example: http://192.168.1.20:8000':
      'هذا ليس عنوانًا صالحًا. مثال: http://192.168.1.20:8000',
  'localhost cannot be used. Enter the network address of the PC that runs the server, for example http://192.168.1.20:8000':
      'لا يمكن استخدام localhost. أدخل عنوان الشبكة للكمبيوتر الذي يشغّل الخادم، مثل http://192.168.1.20:8000',
  'Add the port number. Example: http://192.168.1.20:8000':
      'أضف رقم المنفذ. مثال: http://192.168.1.20:8000',
  'Enter only the address and the port, with nothing after them.':
      'أدخل العنوان والمنفذ فقط، دون أي شيء بعدهما.',
  'Connected to the Excelence server.':
      'تم الاتصال بخادم Excelence.',
  'Cannot reach the server. Check that it is running, that this device is on the same network, and that the address is right.':
      'تعذّر الوصول إلى الخادم. تحقق من أنه يعمل، وأن هذا الجهاز على الشبكة نفسها، وأن العنوان صحيح.',
  'The server did not answer in time. Check the address and the network, then try again.':
      'لم يستجب الخادم في الوقت المناسب. تحقق من العنوان والشبكة ثم حاول مرة أخرى.',
  'The server refused the access token. Check the token and try again.':
      'رفض الخادم رمز الوصول. تحقق من الرمز وحاول مرة أخرى.',
  'Something answered, but it is not an Excelence server. Check the address and the port.':
      'استجاب شيء ما لكنه ليس خادم Excelence. تحقق من العنوان والمنفذ.',
  'Could not apply the new address. Please try again.':
      'تعذّر تطبيق العنوان الجديد. حاول مرة أخرى.',
  'Your open document could not be saved first, so the address was not changed. Try again.':
      'تعذّر حفظ المستند المفتوح أولًا، لذلك لم يتغير العنوان. حاول مرة أخرى.',
};
