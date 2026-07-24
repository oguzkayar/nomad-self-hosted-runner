# Nomad + Consul ile İsim Tabanlı Backend İletişimi

Bu laboratuvarda iki basit Node.js backend'i Docker imajı olarak paketleyip Nomad ile çalıştıracağız. `weather-gateway`, `weather-service` backend'inin IP adresini veya host portunu kaynak kodunda bilmez. Nomad, servisi Consul kataloğuna **`weather-service` adıyla** kaydeder; gateway job'ındaki Consul Template bu adı çözer ve güncel adresi çalışma anında gateway container'ına verir.

> Bu proje eğitim ve yerel geliştirme içindir. Dev mode ayarları üretim ortamı için uygun değildir.

## 1. Mimari

```text
Kullanıcı
   |
   | GET http://127.0.0.1:8080/api/weather/Ankara
   v
weather-gateway
   |
   | 1) Nomad Template -> Consul kataloğunda "weather-service" sorgusu
   | 2) Consul sağlıklı instance adresini ve dinamik portu döndürür
   | 3) Gateway HTTP isteğini çözülmüş adrese yollar
   v
weather-service
```

### Bileşenler

| Bileşen | Görevi |
|---|---|
| `weather-service` | Hava durumu verisi döndüren asıl backend |
| `weather-gateway` | Dış istemciye açık backend; weather-service'i çağırır |
| Nomad | Container'ları planlar, başlatır, port tahsis eder ve yaşam döngüsünü yönetir |
| Consul | Servis adlarını, instance adreslerini ve sağlık durumlarını tutar |
| Consul Template | `weather-service` adını Consul'da sorgular ve sonucu gateway ortam değişkenine yazar |

## 2. Neden sabit IP kullanmıyoruz?

Nomad bir allocation yeniden başladığında container değişebilir ve host portu yeniden tahsis edilebilir. Kaynak kodda `192.168.x.x:23456` gibi bir adres tutarsak yeniden planlama sonrasında bağlantı bozulur. Consul kataloğunda ise mantıksal servis adı sabit kalır:

```text
weather-service -> 192.168.1.20:27841
```

Instance değişirse Consul kaydı güncellenir; gateway job'ındaki template de değişikliği görerek gateway'i yeni adresle yeniden başlatır.

## 3. Ön koşullar

Aşağıdaki komutların çıktı vermesi gerekir:

```bash
docker version
nomad version
consul version
```

Ayrıca Docker Desktop çalışıyor olmalıdır.

## 4. Projeyi açın

```bash
unzip nomad-consul-weather-lab.zip
cd nomad-consul-weather-lab
```

Dizinler:

```text
weather-service/          # Birinci backend
weather-gateway/          # İkinci backend
nomad/                    # Nomad job dosyaları
scripts/                  # Build, deploy, test ve cleanup scriptleri
```

## 5. Docker imajlarını oluşturun

```bash
./scripts/build-images.sh
```

Script şu iki yerel imajı üretir:

```text
nomad-weather-service:1.0
nomad-weather-gateway:1.0
```

Kontrol:

```bash
docker image inspect nomad-weather-service:1.0 >/dev/null && echo OK
docker image inspect nomad-weather-gateway:1.0 >/dev/null && echo OK
```

### Neden önce imaj oluşturuyoruz?

Nomad job dosyalarında bu imaj adları kullanılır. İmaj yerel Docker daemon'ında bulunmazsa Docker driver registry'den çekmeye çalışır ve şu tür hata oluşur:

```text
pull access denied ... repository does not exist
```

Job dosyalarında `force_pull = false` vardır. Bununla birlikte imajın, Nomad'ın bağlandığı **aynı Docker context/daemon** içinde önceden bulunması gerekir.

Kontrol edin:

```bash
docker context show
docker image ls | grep nomad-weather
```

## 6. Consul geliştirme ajanını başlatın

Yeni bir terminal açın:

```bash
consul agent -dev -ui
```

Bu terminal açık kalmalıdır.

Kontrol:

```bash
consul members
curl http://127.0.0.1:8500/v1/status/leader
```

Consul UI:

```text
http://127.0.0.1:8500/ui
```

### Neden Consul'u önce başlatıyoruz?

Nomad, job içindeki `provider = "consul"` servislerini Consul kataloğuna kaydeder. Ayrıca gateway'in `template` bloğu Consul'a sorgu yapar. Consul çalışmıyorsa servis kaydı ve isim çözümleme yapılamaz.

## 7. Nomad geliştirme ajanını başlatın

Başka bir terminal açın:

```bash
sudo nomad agent -dev \
  -bind 0.0.0.0 \
  -network-interface='{{ GetDefaultInterfaces | attr "name" }}'
```

macOS'ta allocation dizini için `permission denied` görürseniz aynı komutu `sudo` olmadan çalıştırın:

```bash
nomad agent -dev \
  -bind 0.0.0.0 \
  -network-interface='{{ GetDefaultInterfaces | attr "name" }}'
```

Bu terminal de açık kalmalıdır.

Üçüncü terminalde:

```bash
export NOMAD_ADDR=http://127.0.0.1:4646
nomad node status
nomad node status -self
```

`Drivers` bölümünde Docker'ın `healthy` olması gerekir.

Nomad UI:

```text
http://127.0.0.1:4646/ui
```

### Neden loopback dışındaki ağ arayüzü kullanılıyor?

`127.0.0.1`, bulunduğu network namespace'in kendisini ifade eder. Farklı container'lardaki iki servis için aynı `127.0.0.1` aynı makineyi temsil etmez. Nomad'ın erişilebilir bir host arayüzünü ilan etmesi, host'a yönlendirilen dinamik portların diğer allocation tarafından erişilebilir olmasını sağlar.

Bu, adresin otomatik olarak internete yayımlandığı anlamına gelmez; fakat aynı yerel ağdaki cihazlardan erişim ihtimali oluşabilir. Bu nedenle geliştirme ajanını güvenilmeyen/açık bir ağda çalıştırmayın ve işletim sistemi güvenlik duvarını kullanın.

## 8. Job dosyalarını doğrulayın

```bash
nomad job validate nomad/weather-service.nomad.hcl
nomad job validate nomad/weather-gateway.nomad.hcl
```

Her iki komut da başarıyla tamamlanmalıdır.

## 9. Önce weather-service'i dağıtın

```bash
nomad job run nomad/weather-service.nomad.hcl
```

Kontrol:

```bash
nomad job status weather-service
consul catalog services
consul catalog nodes -service=weather-service
```

Consul UI'da `weather-service` görünmeli ve sağlık kontrolü kısa süre içinde passing olmalıdır.

### Job dosyasında ne oluyor?

```hcl
service {
  name     = "weather-service"
  provider = "consul"
  port     = "http"
}
```

- `name`: Diğer servislerin kullanacağı mantıksal ad.
- `provider = "consul"`: Kaydın Nomad'ın yerleşik kataloğuna değil Consul'a yapılacağını belirtir.
- `port = "http"`: Nomad'ın dinamik olarak tahsis ettiği host portunu servis kaydına bağlar.
- `/health` kontrolü: Consul'un sağlıksız instance'ı ayırt etmesini sağlar.

## 10. Gateway'i dağıtın

```bash
nomad job run nomad/weather-gateway.nomad.hcl
```

Kontrol:

```bash
nomad job status weather-gateway
consul catalog services
```

Gateway job'ındaki kritik bölüm:

```hcl
template {
  destination = "secrets/upstream.env"
  env         = true
  change_mode = "restart"

  data = <<-EOH
  {{- range service "weather-service|passing" }}
  WEATHER_SERVICE_URL=http://{{ .Address }}:{{ .Port }}
  {{- end }}
  EOH
}
```

Burada:

1. `service "weather-service|passing"`, Consul kataloğunu **servis adıyla** sorgular ve yalnızca sağlık kontrolü geçen instance’ları seçer.
2. `.Address` ve `.Port`, o anda kayıtlı instance'ın gerçek bağlantı bilgisidir.
3. `env = true`, çıktıdaki `WEATHER_SERVICE_URL=...` satırını container ortam değişkenine dönüştürür.
4. `change_mode = "restart"`, kayıt değişirse gateway allocation'ını yeni adresle yeniden başlatır.

Gateway kaynak kodunda Nomad node IP'si veya dinamik port bulunmaz.

## 11. Sistemi test edin

```bash
./scripts/test.sh
```

Manuel test:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/api/weather/Ankara
curl http://127.0.0.1:8080/api/weather/Istanbul
```

Beklenen akış:

```text
curl -> weather-gateway -> weather-service -> weather-gateway -> curl
```

Örnek yanıt:

```json
{
  "gateway": "weather-gateway",
  "discoveredBy": "Consul service catalog",
  "upstreamServiceName": "weather-service",
  "data": {
    "city": "Ankara",
    "temperatureC": 23,
    "condition": "Parçalı bulutlu",
    "source": "weather-service"
  }
}
```

## 12. Logları inceleyin

Allocation ID'lerini bulun:

```bash
nomad job allocs weather-service
nomad job allocs weather-gateway
```

Log:

```bash
nomad alloc logs <WEATHER_SERVICE_ALLOC_ID>
nomad alloc logs <WEATHER_GATEWAY_ALLOC_ID>
```

Hata logları:

```bash
nomad alloc logs -stderr <ALLOC_ID>
```

## 13. Consul kaydını doğrudan doğrulayın

```bash
consul catalog nodes -service=weather-service -detailed
```

DNS kaydı da Consul üzerinde vardır:

```bash
dig @127.0.0.1 -p 8600 weather-service.service.consul
```

Bu laboratuvar gateway container'ında doğrudan Consul DNS kullanmaz. Bunun nedeni Docker Desktop container DNS resolver'ının Consul'un varsayılan `8600` portuna otomatik olarak yönlendirilmemesidir. İsim çözümlemesini Nomad Template üzerinden yapmak, ek host DNS yapılandırmasına ihtiyaç bırakmaz.

## 14. Yeniden planlama davranışını gözlemleyin

Weather service allocation'ını durdurun:

```bash
nomad job restart -yes weather-service
```

Ardından:

```bash
nomad job status weather-service
nomad job status weather-gateway
curl http://127.0.0.1:8080/api/weather/Ankara
```

Weather service adresi/portu değişirse template yeniden render edilir ve gateway yeni değerle yeniden başlatılır. Kodda IP değiştirme gerekmez.

## 15. Sık karşılaşılan hatalar

### A. `pull access denied for nomad-weather-service`

Neden: İmaj Nomad'ın kullandığı Docker daemon/context içinde yoktur.

```bash
docker context show
docker image inspect nomad-weather-service:1.0
./scripts/build-images.sh
```

İmaj adının job dosyasındaki adla birebir aynı olduğundan emin olun.

### B. `missing drivers: docker`

```bash
docker version
ls -l /var/run/docker.sock
nomad node status -self
```

Docker Desktop açık olmalı ve `/var/run/docker.sock` bağlantısı bulunmalıdır.

### C. macOS mount `permission denied`

Nomad ajanını `sudo` olmadan çalıştırmayı deneyin. Docker Desktop ayarlarında gerekli dosya paylaşım izinlerini kontrol edin.

### D. Gateway `Upstream servis adresi henüz ... çözülemedi` diyor

Önce weather-service job'unun ve Consul health check'in passing olduğunu doğrulayın:

```bash
nomad job status weather-service
consul catalog nodes -service=weather-service
```

Gateway'i yeniden başlatın:

```bash
nomad job restart -yes weather-gateway
```

### E. `127.0.0.1` neden backendler arasında çalışmıyor?

Her container'ın kendi loopback arayüzü vardır. Gateway container'ındaki `127.0.0.1`, weather-service container'ı değil gateway container'ının kendisidir. Aynı task group ve aynı network namespace kullanılmadıkça farklı container'lar loopback üzerinden birbirine erişemez.

### F. `static port 8080` kullanımda

Gateway job dosyasında:

```hcl
static = 8080
```

satırını boş dinamik porta dönüştürebilirsiniz:

```hcl
port "http" {
  to = 3000
}
```

Sonra gateway adresini şu komutla bulun:

```bash
nomad job status weather-gateway
```

## 16. Temizleme

```bash
./scripts/cleanup.sh
```

Ardından Nomad ve Consul terminallerinde `Ctrl+C` kullanın.

İmajları da silmek isterseniz:

```bash
docker image rm nomad-weather-service:1.0 nomad-weather-gateway:1.0
```

## 17. Bu yapının sınırı

Bu başlangıç örneği tek weather-service instance'ı kullanır. Birden çok instance çalıştırıldığında template birden fazla satır üretebilir ve gelişmiş yük dengeleme gerekir. Üretime yakın yaklaşım için şu seçeneklerden biri kullanılmalıdır:

- Consul DNS + DNS SRV kayıtları,
- Consul Service Mesh/Connect + Envoy sidecar,
- Consul-aware reverse proxy/load balancer,
- Uygulama içinde Consul health API üzerinden client-side load balancing.

## Resmî kaynaklar

- Nomad Service Discovery: https://developer.hashicorp.com/nomad/docs/networking/service-discovery
- Nomad Service Block: https://developer.hashicorp.com/nomad/docs/job-specification/service
- Nomad Template Block: https://developer.hashicorp.com/nomad/docs/job-specification/template
- Nomad Docker Driver: https://developer.hashicorp.com/nomad/docs/job-declare/task-driver/docker
- Consul DNS: https://developer.hashicorp.com/consul/docs/discover/dns
- Nomad local cluster tutorial: https://developer.hashicorp.com/nomad/tutorials/get-started/gs-start-a-cluster
