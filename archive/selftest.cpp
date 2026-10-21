// Самотест архиватора: build/archive/glide-archive-selftest ПАПКА (пустая или несуществующая).
// Для каждого формата: создать архив из дерева файлов → прочитать список → распаковать всё и выбранное →
// сравнить содержимое побайтно. Плюс: пароль zip, архивы чужими программами (7z, zip, tar), опасные пути.
#include "archiver.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QVariantMap>
#include <cstdio>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::fprintf(stderr, "  ✗ %s:%d %s — ", __FILE__, __LINE__, #cond); \
    std::fprintf(stderr, __VA_ARGS__); std::fputc('\n', stderr); } } while (0)

static void write(const QString &path, const QByteArray &data)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    (void)f.open(QIODevice::WriteOnly);
    f.write(data);
}

// содержимое дерева: относительный путь → хэш (папки — «dir», ссылки — «->цель»)
static QMap<QString, QByteArray> snapshot(const QString &root)
{
    QMap<QString, QByteArray> m;
    QDirIterator it(root, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString p = it.next();
        const QFileInfo fi = it.fileInfo();
        const QString rel = p.mid(root.size() + 1);
        if (fi.isSymLink())
            m[rel] = "->" + fi.readSymLink().toUtf8();
        else if (fi.isDir())
            m[rel] = "dir";
        else {
            QFile f(p);
            (void)f.open(QIODevice::ReadOnly);
            m[rel] = QCryptographicHash::hash(f.readAll(), QCryptographicHash::Sha256).toHex();
        }
    }
    return m;
}

static QString diff(const QMap<QString, QByteArray> &a, const QMap<QString, QByteArray> &b)
{
    QStringList out;
    for (auto it = a.begin(); it != a.end(); ++it)
        if (!b.contains(it.key())) out << "нет " + it.key();
        else if (b[it.key()] != it.value()) out << "другое " + it.key();
    for (auto it = b.begin(); it != b.end(); ++it)
        if (!a.contains(it.key())) out << "лишнее " + it.key();
    return out.mid(0, 6).join(", ");
}

static QString clean(const QString &dir)
{
    QDir(dir).removeRecursively();
    QDir().mkpath(dir);
    return dir;
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const QString base = QFileInfo(argc > 1 ? argv[1] : "archive-selftest").absoluteFilePath();
    QDir(base).removeRecursively();

    // исходное дерево: русские имена, пробелы, пустой файл и папка, крупный несжимаемый файл, ссылка
    const QString src = base + "/src/Проект";
    write(src + "/readme.txt", "привет, архив\n");
    write(src + "/пустой", "");
    write(src + "/docs/глава 1.md", QByteArray(20000, 'a'));
    write(src + "/docs/вложено/deep.bin", QByteArray("\x00\x01\x02\xff", 4).repeated(1000));
    QByteArray noise(3 * 1024 * 1024, Qt::Uninitialized);
    for (char &c : noise) c = char(QRandomGenerator::global()->generate());
    write(src + "/big.dat", noise);
    write(src + "/.hidden", "h");
    QDir().mkpath(src + "/пустая папка");
    QFile::link("readme.txt", src + "/link-to-readme");
    write(base + "/src/second.txt", "второй источник");
    const auto expected = snapshot(base + "/src");

    const QStringList sources{src, base + "/src/second.txt"};
    const QStringList formats{"zip", "7z", "tar.zst", "tar.xz", "tar.gz"};
    for (const QString &fmt : formats) {
        std::printf("— %s\n", qPrintable(fmt));
        const QString arc = base + "/out/test." + fmt;
        QDir().mkpath(base + "/out");
        qreal lastP = 0;
        int calls = 0;
        QString err = Archive::createSync(sources, arc, fmt, QString(), nullptr, [&](qreal p) { lastP = p; ++calls; });
        CHECK(err.isEmpty(), "создание: %s", qPrintable(err));
        CHECK(lastP == 1 && calls > 2, "прогресс создания %f за %d", lastP, calls);
        CHECK(!QFile::exists(arc + ".part"), "остался .part");

        Archive::Listing l;
        err = Archive::listSync(arc, QString(), &l);
        CHECK(err.isEmpty(), "список: %s", qPrintable(err));
        QStringList paths;
        for (const QVariant &v : l.entries) paths << v.toMap().value("path").toString();
        CHECK(paths.contains("Проект/docs/вложено/deep.bin"), "нет deep.bin в списке");
        CHECK(paths.contains("Проект/пустая папка"), "нет пустой папки в списке");
        CHECK(paths.contains("second.txt"), "нет second.txt");
        CHECK(l.total >= noise.size(), "сумма размеров %lld", l.total);
        CHECK(l.entries.first().toMap().value("dir").toBool(), "папки не сверху");
        for (const QVariant &v : l.entries)
            if (v.toMap().value("path") == "Проект")
                CHECK(v.toMap().value("size").toLongLong() >= noise.size() && v.toMap().value("count").toInt() == 7,
                      "размер/число в папке: %lld %d", v.toMap().value("size").toLongLong(), v.toMap().value("count").toInt());
        std::printf("  формат: %s, записей %lld\n", qPrintable(l.format), qlonglong(l.entries.size()));

        const QString all = clean(base + "/x/" + fmt);
        QString written;
        lastP = 0;
        err = Archive::extractSync(arc, QString(), l.charset, {}, all, &written, nullptr, nullptr, [&](qreal p) { lastP = p; });
        CHECK(err.isEmpty(), "распаковка: %s", qPrintable(err));
        CHECK(lastP == 1, "прогресс распаковки %f", lastP);
        CHECK(written == QFileInfo(all).canonicalFilePath(), "written=%s", qPrintable(written));
        const auto got = snapshot(all);
        CHECK(got == expected, "содержимое: %s", qPrintable(diff(expected, got)));

        // выбранное: папка из глубины и один файл — без пути до них
        const QString sel = clean(base + "/sel/" + fmt);
        err = Archive::extractSync(arc, QString(), l.charset, {"Проект/docs", "Проект/readme.txt"}, sel, &written);
        CHECK(err.isEmpty(), "выбранное: %s", qPrintable(err));
        const auto s = snapshot(sel);
        CHECK(s.keys() == QStringList({"docs", "docs/вложено", "docs/вложено/deep.bin", "docs/глава 1.md", "readme.txt"}),
              "выбранное: %s", qPrintable(QStringList(s.keys()).join(", ")));
        // повтор в ту же папку — не затирает, а кладёт «(2)»
        err = Archive::extractSync(arc, QString(), l.charset, {"Проект/readme.txt"}, sel, &written);
        CHECK(err.isEmpty() && QFile::exists(sel + "/readme (2).txt") && written.endsWith("readme (2).txt"),
              "повтор: %s %s", qPrintable(err), qPrintable(written));

        // отмена посреди: ошибка «cancelled», недописанного файла нет
        std::atomic<bool> cancel{false};
        const QString canc = clean(base + "/cancel/" + fmt);
        err = Archive::extractSync(arc, QString(), l.charset, {}, canc, nullptr, nullptr, &cancel, [&](qreal p) { if (p > 0.05) cancel = true; });
        if (err == "cancelled") {
            const auto c = snapshot(canc);
            CHECK(!c.contains("Проект/big.dat") || c["Проект/big.dat"] == expected["Проект/big.dat"], "недописанный big.dat");
        }
    }

    // ---- пароль zip (AES-256)
    std::printf("— zip с паролем\n");
    {
        const QString arc = base + "/out/secret.zip";
        QString err = Archive::createSync({base + "/src/second.txt"}, arc, "zip", "пароль-123");
        CHECK(err.isEmpty(), "создание: %s", qPrintable(err));
        Archive::Listing l;
        err = Archive::listSync(arc, QString(), &l);
        CHECK(err.isEmpty() && l.encrypted, "список без пароля: %s enc=%d", qPrintable(err), l.encrypted);
        err = Archive::listSync(arc, "не тот", &l);
        CHECK(err == "wrong-password", "неверный пароль при открытии: %s", qPrintable(err));
        const QString d = clean(base + "/x/secret");
        err = Archive::extractSync(arc, QString(), QString(), {}, d);
        CHECK(err == "password", "без пароля: %s", qPrintable(err));
        err = Archive::extractSync(arc, "не тот", QString(), {}, d);
        CHECK(err == "wrong-password", "неверный: %s", qPrintable(err));
        CHECK(!QFile::exists(d + "/second.txt"), "остался файл после неверного пароля");
        err = Archive::extractSync(arc, "пароль-123", QString(), {}, d);
        CHECK(err.isEmpty() && snapshot(d).value("second.txt") == expected["second.txt"], "верный: %s", qPrintable(err));
        if (!QStandardPaths::findExecutable("7z").isEmpty()) {   // открывается ли чужой программой
            const int rc = QProcess::execute("7z", {"t", "-p" + QStringLiteral("пароль-123"), "-bso0", "-bsp0", arc});
            CHECK(rc == 0, "7z t вернул %d", rc);
        }
        err = Archive::createSync({base + "/src/second.txt"}, base + "/out/secret.7z", "7z", "x");
        CHECK(!err.isEmpty(), "пароль на 7z должен отклоняться");
    }

    // ---- архивы, сделанные другими программами
    if (!QStandardPaths::findExecutable("zip").isEmpty()) {
        std::printf("— info.zip (zip)\n");
        const QString arc = base + "/out/info.zip";
        QProcess p;
        p.setWorkingDirectory(base + "/src");
        p.start("zip", {"-r", "-q", "-y", arc, "Проект", "second.txt"});
        p.waitForFinished(60000);
        const QString d = clean(base + "/x/info");
        Archive::Listing l;
        QString err = Archive::listSync(arc, QString(), &l);
        err += Archive::extractSync(arc, QString(), l.charset, {}, d);
        CHECK(err.isEmpty() && snapshot(d) == expected, "info.zip: %s %s", qPrintable(err), qPrintable(diff(expected, snapshot(d))));
    }
    if (!QStandardPaths::findExecutable("7z").isEmpty()) {
        std::printf("— 7z.7z (7z)\n");
        const QString arc = base + "/out/7z.7z";
        QProcess::execute("7z", {"a", "-bso0", "-bsp0", "-snl", arc, base + "/src/Проект", base + "/src/second.txt"});
        const QString d = clean(base + "/x/7z-native");
        Archive::Listing l;
        QString err = Archive::listSync(arc, QString(), &l);
        CHECK(err.isEmpty(), "список: %s", qPrintable(err));
        err = Archive::extractSync(arc, QString(), l.charset, {}, d);
        CHECK(err.isEmpty() && snapshot(d) == expected, "7z → распаковка: %s %s", qPrintable(err), qPrintable(diff(expected, snapshot(d))));
        // зашифрованный 7z: libarchive не расшифровывает — должна быть понятная ошибка, а не мусор
        const QString enc = base + "/out/enc.7z";
        QProcess::execute("7z", {"a", "-bso0", "-bsp0", "-pqwe", "-mhe=on", enc, base + "/src/second.txt"});
        err = Archive::listSync(enc, QString(), &l);
        std::printf("  зашифрованный 7z без пароля: %s\n", qPrintable(err));
        CHECK(err == "password", "enc.7z без пароля: %s", qPrintable(err));
        err = Archive::listSync(enc, "не тот", &l);
        CHECK(err == "wrong-password", "enc.7z неверный: %s", qPrintable(err));
        err = Archive::listSync(enc, "qwe", &l);
        CHECK(err.isEmpty() && l.charset == "7z" && l.entries.size() == 1 && l.encrypted, "enc.7z верный: %s", qPrintable(err));
        QString dd = clean(base + "/x/enc7z");
        err = Archive::extractSync(enc, "qwe", l.charset, {}, dd);
        CHECK(err.isEmpty() && snapshot(dd).value("second.txt") == expected["second.txt"], "enc.7z распаковка: %s", qPrintable(err));
        // шифровано только содержимое (имена открыты): список — libarchive, распаковка — 7-Zip
        const QString enc2 = base + "/out/enc2.7z";
        QProcess::execute("7z", {"a", "-bso0", "-bsp0", "-pqwe", enc2, base + "/src/Проект"});
        err = Archive::listSync(enc2, QString(), &l);
        CHECK(err.isEmpty() && l.encrypted, "enc2 список: %s", qPrintable(err));
        dd = clean(base + "/x/enc2");
        err = Archive::extractSync(enc2, QString(), l.charset, {}, dd);
        CHECK(err == "password", "enc2 без пароля: %s", qPrintable(err));
        err = Archive::listSync(enc2, "qwe", &l);
        CHECK(err.isEmpty(), "enc2 список с паролем: %s", qPrintable(err));
        err = Archive::extractSync(enc2, "qwe", l.charset, {"Проект/docs"}, dd);
        CHECK(err.isEmpty() && snapshot(dd).keys() == QStringList({"docs", "docs/вложено", "docs/вложено/deep.bin", "docs/глава 1.md"}),
              "enc2 выбранное: %s %s", qPrintable(err), qPrintable(QStringList(snapshot(dd).keys()).join(", ")));
        err = Archive::extractSync(enc2, "zzz", l.charset, {}, clean(base + "/x/enc2bad"));
        CHECK(err == "wrong-password", "enc2 неверный: %s", qPrintable(err));
    }
    if (!QStandardPaths::findExecutable("tar").isEmpty()) {
        std::printf("— tar.bz2 (tar)\n");
        const QString arc = base + "/out/gnu.tar.bz2";
        QProcess::execute("tar", {"-C", base + "/src", "-cjf", arc, "Проект", "second.txt"});
        const QString d = clean(base + "/x/gnu");
        Archive::Listing l;
        QString err = Archive::listSync(arc, QString(), &l);
        err += Archive::extractSync(arc, QString(), l.charset, {}, d);
        CHECK(err.isEmpty() && snapshot(d) == expected, "tar.bz2: %s %s", qPrintable(err), qPrintable(diff(expected, snapshot(d))));
    }

    // ---- одиночный сжатый файл (raw): file.txt.gz → file.txt
    if (!QStandardPaths::findExecutable("gzip").isEmpty()) {
        std::printf("— one.txt.gz (raw)\n");
        QFile::copy(base + "/src/second.txt", base + "/out/one.txt");
        QProcess::execute("gzip", {"-f", base + "/out/one.txt"});
        Archive::Listing l;
        QString err = Archive::listSync(base + "/out/one.txt.gz", QString(), &l);
        CHECK(err.isEmpty() && l.entries.size() == 1 && l.entries[0].toMap().value("path") == "one.txt",
              "raw список: %s %lld", qPrintable(err), qlonglong(l.entries.size()));
        const QString d = clean(base + "/x/raw");
        err = Archive::extractSync(base + "/out/one.txt.gz", QString(), QString(), {}, d);
        CHECK(err.isEmpty() && snapshot(d).value("one.txt") == expected["second.txt"], "raw: %s", qPrintable(err));
        // не архив вовсе
        err = Archive::listSync(base + "/src/second.txt", QString(), &l);
        CHECK(!err.isEmpty(), "текстовый файл принят за архив");
    }

    // ---- опасные пути: «../» и абсолютные не выходят за папку
    if (!QStandardPaths::findExecutable("python3").isEmpty()) {
        std::printf("— опасные пути\n");
        const QString arc = base + "/out/evil.tar";
        QProcess::execute("python3", {"-c",
            "import tarfile,io,sys\n"
            "t=tarfile.open(sys.argv[1],'w')\n"
            "def add(n,d=b'x'):\n"
            "  i=tarfile.TarInfo(n); i.size=len(d); t.addfile(i,io.BytesIO(d))\n"
            "add('../escape.txt'); add('/tmp/glide-abs-escape.txt'); add('ok/../../escape2.txt'); add('good.txt')\n"
            "l=tarfile.TarInfo('lnk'); l.type=tarfile.SYMTYPE; l.linkname='..'; t.addfile(l)\n"
            "add('lnk/escape3.txt')\n"
            "t.close()", arc});
        const QString d = clean(base + "/x/evil/inner");
        QFile::remove("/tmp/glide-abs-escape.txt");
        QStringList skipped;
        const QString err = Archive::extractSync(arc, QString(), QString(), {}, d, nullptr, &skipped);
        std::printf("  ответ: %s, пропущено: %s\n", err.isEmpty() ? "ok" : qPrintable(err), qPrintable(skipped.join(", ")));
        CHECK(err.isEmpty() && skipped.size() == 3, "пропущено %lld", qlonglong(skipped.size()));
        CHECK(!QFile::exists(base + "/x/evil/escape.txt") && !QFile::exists(base + "/x/escape2.txt")
              && !QFile::exists(base + "/x/evil/escape3.txt") && !QFile::exists("/tmp/glide-abs-escape.txt"),
              "файл вышел за папку");
        CHECK(QFile::exists(d + "/good.txt") || !err.isEmpty(), "good.txt не распакован");
        CHECK(QFile::exists(d + "/tmp/glide-abs-escape.txt") || !err.isEmpty(), "абсолютный путь не переложен внутрь");
    }

    // ---- zip из Windows с именами в CP866
    if (!QStandardPaths::findExecutable("python3").isEmpty()) {
        std::printf("— zip с именами CP866\n");
        const QString arc = base + "/out/cp866.zip";
        QProcess::execute("python3", {"-c",
            "import zipfile,sys\n"
            "z=zipfile.ZipFile(sys.argv[1],'w')\n"
            "n='Отчёт.txt'.encode('cp866')\n"
            "z.writestr('Q'*len(n),b'data'); z.close()\n"   // ASCII-имя без флага UTF-8 → заменяем байтами CP866
            "b=open(sys.argv[1],'rb').read().replace(b'Q'*len(n),n)\n"
            "open(sys.argv[1],'wb').write(b)", arc});
        Archive::Listing l;
        const QString err = Archive::listSync(arc, QString(), &l);
        const QString name = l.entries.isEmpty() ? QString() : l.entries[0].toMap().value("path").toString();
        std::printf("  имя: %s, кодировка: %s\n", qPrintable(name), qPrintable(l.charset));
        CHECK(err.isEmpty() && name == "Отчёт.txt", "cp866: %s «%s»", qPrintable(err), qPrintable(name));
    }

    std::printf(failures ? "\nОШИБОК: %d\n" : "\nвсё в порядке\n", failures);
    return failures ? 1 : 0;
}
