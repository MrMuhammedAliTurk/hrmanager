# HRManagerDB — İnsan Kaynakları Yönetim Sistemi

## Paket içeriği
- `HRManager_Proje.sql`: Veritabanı, tablolar, örnek veriler, indeksler, görünümler, saklı yordamlar, raporlama sorguları ve isteğe bağlı yedekleme komutu.
- `HRManager_ProjeDokumani.docx`: Proje kapsamı, ilişkisel tasarım, SQL özellikleri ve çalıştırma yönergeleri.
- `HRManager_ERD.png`: Veri tabanı ilişki diyagramı.
- `HRManager_ERD.dot`: ER diyagramının Graphviz kaynak dosyası.

## Çalıştırma
1. SQL Server Developer veya Express kurulu bir SQL Server örneğini başlatın.
2. SQL Server Management Studio (SSMS) ile bağlanın.
3. `HRManager_Proje.sql` dosyasını açıp tamamını çalıştırın.
4. Nesne Gezgini'nde `HRManagerDB` veritabanını yenileyin.
5. Sonuç kümelerini incelemek için dosyanın `BÖLÜM 6 - RAPORLAMA SORGULARI` kısmındaki sorguları ayrı ayrı çalıştırın.

## Önemli notlar
- Script, SQL Server T-SQL içindir; MySQL veya PostgreSQL ile doğrudan uyumlu değildir.
- Örnek çalışan ve e-posta verileri kurgusaldir.
- Yedekleme komutu varsayılan olarak yorum satırındadır. Önce `C:\Yedek` klasörünü oluşturun ve SQL Server servis hesabına yazma izni verin.
- İzin kullanım özeti örnek olarak takvim günleriyle hesaplanır; üretim ortamında hafta sonları ve resmî tatiller için ayrıca takvim mantığı eklenmelidir.
- Bu paket, geliştirme/eğitim amaçlı başlangıç sürümüdür. SQL Server üzerinde gerçek çalıştırma testi ve SSMS sonuç ekran görüntüleri yerel ortamda alınmalıdır.
