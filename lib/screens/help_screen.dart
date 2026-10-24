import 'package:flutter/material.dart';

/// Yardım & Biyometrik / e-Okul Kuralları Rehberi — sekmeli bilgilendirme.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yardım & Kurallar'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'e-Okul'),
              Tab(text: 'Biyometrik'),
              Tab(text: 'Çekim İpuçları'),
              Tab(text: 'Uygulama'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _EokulRules(),
            _BiometricRules(),
            _CaptureTips(),
            _UsageHelp(),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<Widget> children;

  const _Body({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: children,
    );
  }
}

class _H1 extends StatelessWidget {
  final String text;
  const _H1(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 18),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(height: 1.55)),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(
              width: 6,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// e-Okul
// -----------------------------------------------------------------------------

class _EokulRules extends StatelessWidget {
  const _EokulRules();

  @override
  Widget build(BuildContext context) {
    return _Body(children: const [
      _H1('MEB e-Okul Fotoğraf Kuralları'),
      _P('e-Okul sistemi, öğrenci vesikalıklarını belirli formatlarda '
          'kabul eder. Uygulama varsayılan olarak bu kurallara göre kaydeder:'),
      _Bullet('Oran: 3:4 dikey (portre) — kamera kılavuz çerçevesi bu '
          'orana göre çizilir ve yalnızca çerçeve içi alan kaydedilir.'),
      _Bullet('Çözünürlük: 300×400 px (varsayılan) veya 133×171 px — '
          'Ayarlar’dan değiştirilebilir; iki seçenek de temiz 3:4’tür.'),
      _Bullet('Format: JPEG (.jpg) — dosya uzantısı her zaman .jpg olur.'),
      _Bullet('Dosya boyutu: en fazla 50 KB (uygulama 49 KB’ta durur). '
          'JPEG kalitesi, en yüksek kaliteyi koruyacak şekilde otomatik '
          'araştırılır.'),
      _Bullet('Dosya adı: yalnızca okul numarası — ör. 1042.jpg. '
          'Başka karakter yazılmaz.'),
      _H1('Yükleme Sırası'),
      _P('e-Okul’a yüklemede sınıf klasörünü ZIP ile tek seferde '
          'gönderebilirsiniz: ZIP içindeki dosyalar doğrudan .jpg olduğundan '
          'seç- yükle yapılır.'),
      _H1('Uyarılar'),
      _P('Aynı okul numarasına iki kez fotoğraf çekerseniz uygulama '
          'uyarır; isterseniz üzerine yazılır. Numaraları karıştırmamak '
          'için sınıf listesini çekimden önce hazır bulundurun.'),
    ]);
  }
}

// -----------------------------------------------------------------------------
// Biyometrik
// -----------------------------------------------------------------------------

class _BiometricRules extends StatelessWidget {
  const _BiometricRules();

  @override
  Widget build(BuildContext context) {
    return _Body(children: const [
      _H1('ICAO / Biyometrik Fotoğraf Standartı'),
      _P('Pasaport, kimlik kartı, vize ve birçok sınav başvurusu '
          '(ÖSYM, KPSS vb.) ICAO kılavuzlarına göre biyometrik fotoğraf '
          'ister. Uygulamanın Biyometrik Modu bu kurallara göre çalışır:'),
      _Bullet('Oran: 5:6 — yani 50×60 mm standardı (kamera kılavuz '
          'çerçevesi otomatik bu orana geçer).'),
      _Bullet('Çözünürlük: 600×720 px (yüksek kalite) veya 1200×1440 px '
          '(baskı kalitesi) — Ayarlar’dan seçilebilir.'),
      _Bullet('Kalite: %95 JPEG — 50 KB sınırı UYGULANMAZ, sıkıştırma '
          'kaybı minimumda tutulur.'),
      _H1('Kamera Kılavuzu Ne Anlama Geliyor?'),
      _Bullet('Yeşil oval: kafa konturu — yüz bu ovalin içinde ortalanmalı '
          '(hafif nefes animasyonu hedefin canlı olduğunu gösterir).'),
      _Bullet('NEON YEŞİL ŞERİT: gözlerin tam gelmesi gereken yatay '
          'bölgedir — gözler bu bandın içinde olmalı.'),
      _Bullet('Kesikli TEPE çizgisi: saç üstü sınırı; ÇENE çizgisi: '
          'çene altı sınırı.'),
      _Bullet('Dikey çizgi + artı (+): yüzün merkez simetri ekseni — '
          'burun hizası bu çizgi üzerinde olmalı.'),
      _H1('Arka Plan Kuralı (Çok Önemli)'),
      _P('Biyometrik fotoğrafta arka plan DÜZ beyaz (veya çok açık renk), '
          'gölgesiz ve desensiz olmalıdır. Uygulama, fotoğrafı kaydetmeden '
          'önce arka planın parlaklığını ve dalgalılığını ölçer; uygun '
          'değilse uyarı verir.'),
      _H1('Yüz İfadesi ve Giyim'),
      _Bullet('Nötr ifade: gülümsemeyin, ağzı kapalı, dudaklar bitişik.'),
      _Bullet('Baş dik ve kameraya tam dönük; gözlüklüysüz camlarda '
          'parlama olmamalı.'),
      _Bullet('Saç yüzü kapatmamalı; her iki kulak görünür olmalı '
          '(mümkünse).'),
      _Bullet('Yaka, gömlek yakası veya ceket tercih edilir; açık renk '
          'üst kıyafet uygundur.'),
    ]);
  }
}

// -----------------------------------------------------------------------------
// İpuçları
// -----------------------------------------------------------------------------

class _CaptureTips extends StatelessWidget {
  const _CaptureTips();

  @override
  Widget build(BuildContext context) {
    return _Body(children: const [
      _H1('Karanlık Sınıfta Çekim'),
      _Bullet('Alt kısımdaki PARIKLAKLIK (☀) kaydırıcısını çekmeden önce '
          'yukarı kaydırın — karanlık okul koridorlarında görüntü anında '
          'aydınlanır.'),
      _Bullet('Flaş düğmesi: Kapalı → Otomatik → Açık → FENER (torch). '
          'Fener modu, arka kamerada sürekli ışık sağlar.'),
      _Bullet('Yine de karanlık çıkarsa onay ekranındaki "Parlaklık & '
          'Kontrast İyileştir" anahtarını açın — görsel otomatik '
          'aydınlatılır ve yeniden ölçülür.'),
      _H1('Seri Çekim (Hızlı)'),
      _Bullet('Kaydettiğiniz son okul numarası ekranda gösterilir; sıradaki '
          'numara otomatik olarak (bir fazlası) önerilir — klavye '
          'girmeniz yeterli.'),
      _Bullet('Kamera kaydı kapatmaz: Kaydet düğmesine bastıktan sonra '
          'vizör açık kalır, doğrudan sıradaki öğrenciye geçebilirsiniz.'),
      _Bullet('Geri sayım (Ayarlar → 3 sn): deklanşöre bastığınızda '
          'büyük rakamlarla geri sayım başlar; kendinizi hazırlayın.'),
      _H1('Odak ve Netlik'),
      _Bullet('Vizörde yüzün olduğu noktaya dokunarak odak ve pozlama '
          'kilitleyin.'),
      _Bullet('Net değilse sağ alttaki + düğmesiyle odağı yenileyin.'),
      _H1('Yanlış Çekim'),
      _Bullet('Onay ekranında "Yeniden Çek"e basın — fotoğraf kaydedilmez, '
          'vizör aynı kalır.'),
      _Bullet('Kayıttan sonra: galeride fotoğrafa dokunup Sil veya '
          'Yeniden Çek seçebilirsiniz.'),
    ]);
  }
}

// -----------------------------------------------------------------------------
// Uygulama kullanımı
// -----------------------------------------------------------------------------

class _UsageHelp extends StatelessWidget {
  const _UsageHelp();

  @override
  Widget build(BuildContext context) {
    return _Body(children: const [
      _H1('Sınıf Yönetimi'),
      _Bullet('Ana ekranın sağ alttaki "Yeni Sınıf Ekle" düğmesiyle sınıf '
          'açın (örn. 5-A). Sınıflar cihazda eOkulFoto/ klasörü altında '
          'tutulur.'),
      _Bullet('Sınıf kartındaki Fotoğraf Çek / ZIP / Sil düğmeleri hızlı '
          'işlem içindir; karta dokunursanız galeri açılır.'),
      _H1('ZIP ile Paylaşım'),
      _Bullet('Tek sınıf: sınıf kartı → ZIP / Paylaş, veya galeri üst '
          'barındaki ZIP düğmesi. Dosyalar [Sınıf]_eOkul_Fotograflari.zip '
          'adıyla WhatsApp/Drive/e-posta paylaşım menüsüyle gönderilir.'),
      _Bullet('Tüm okul: yan menüden "Tüm Okulu Tek ZIP" — her şey '
          'SınıfAdı/OkulNo.jpg klasör yapısıyla tek arşivde toplanır.'),
      _H1('Dönüştürme ve Baskı'),
      _Bullet('Biyometrik çekilmiş fotoğraflarınızı galeride '
          '"e-Okul Formatına Dönüştür" ile 300×400 / <50 KB ZIP’ine '
          'çevirebilirsiniz — tek çekimde hem biyometrik arşiv hem e-Okul '
          'paketiniz olur.'),
      _Bullet('"Fotoğraflı Sınıf Listesi" tüm fotoğrafları numaralarıyla '
          'tek tablo JPG’sinde toplar (yazıcı için).'),
      _Bullet('Öğrenci fotoğrafının detayında "Baskı Şablonu" 10×15 cm '
          'kağıda 8 adet, kesim çizgili düzen üretir.'),
      _H1('Gizlilik ve Güvenlik'),
      _P('Tüm fotoğraflar yalnızca bu uygulamanın özel klasöründe '
          'tutulur; başka uygulamalar erişemez. Paylaşımlar sizin '
          'onayınızla, cihazın paylaşım menüsü üzerinden yapılır. '
          'Önemli arşivlerinizi ZIP olarak yedeklemenizi öneririz.'),
    ]);
  }
}
