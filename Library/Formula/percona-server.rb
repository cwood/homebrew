require 'formula'

class PerconaServer < Formula
  homepage 'http://www.percona.com'
  url 'http://www.percona.com/redir/downloads/Percona-Server-5.6/LATEST/release-5.6.14-62.0/483/source/Percona-Server-5.6.14-rel62.0.tar.gz'
  version '5.6.14-rel62.0'
  sha1 '6d9ddd92338c70ec13bdeb9a23568a990a5766f9'

  depends_on 'cmake' => :build
  depends_on 'readline'
  depends_on 'pidof'

  option :universal
  option 'with-tests', 'Build with unit tests'
  option 'with-embedded', 'Build the embedded server'
  option 'with-libedit', 'Compile with editline wrapper instead of readline'
  option 'enable-local-infile', 'Build with local infile loading support'


  conflicts_with 'mariadb', 'mysql', 'mysql-cluster',
    :because => "percona, mariadb, and mysql install the same binaries."

  env :std if build.universal?

  fails_with :llvm do
    build 2334
    cause "https://github.com/mxcl/homebrew/issues/issue/144"
  end

  # Where the database files should be located. Existing installs have them
  # under var/percona, but going forward they will be under var/msyql to be
  # shared with the mysql and mariadb formulae.
  def destination
    @destination ||= (var/'percona').directory? ? 'percona' : 'mysql'
  end

  def patches
    # Fixes percona server 5.6 compilation on OS X 10.9, based on
    # https://github.com/mxcl/homebrew/commit/aad5d93f4fabbf69766deb83780d3a6eeab7061a
    # for mysql 5.6
    "https://gist.github.com/israelshirk/7cc640498cf264ebfce3/raw/846839c84647c4190ad683e4cbf0fabcd8931f97/gistfile1.txt"
  end

  def install
    # Build without compiler or CPU specific optimization flags to facilitate
    # compilation of gems and other software that queries `mysql-config`.
    ENV.minimal_optimization

    # Make sure that data directory exists
    (var/destination).mkpath

    args = [
      ".",
      "-DCMAKE_INSTALL_PREFIX=#{prefix}",
      "-DMYSQL_DATADIR=#{var}/#{destination}",
      "-DINSTALL_MANDIR=#{man}",
      "-DINSTALL_DOCDIR=#{doc}",
      "-DINSTALL_INFODIR=#{info}",
      # CMake prepends prefix, so use share.basename
      "-DINSTALL_MYSQLSHAREDIR=#{share.basename}/mysql",
      "-DWITH_SSL=yes",
      "-DDEFAULT_CHARSET=utf8",
      "-DDEFAULT_COLLATION=utf8_general_ci",
      "-DSYSCONFDIR=#{etc}",
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
      # PAM plugin is Linux-only at the moment
      "-DWITHOUT_AUTH_PAM=1",
      "-DWITHOUT_AUTH_PAM_COMPAT=1",
      "-DWITHOUT_DIALOG=1"
    ]

    # To enable unit testing at build, we need to download the unit testing suite
    if build.include? 'with-tests'
      args << "-DENABLE_DOWNLOADS=ON"
    else
      args << "-DWITH_UNIT_TESTS=OFF"
    end

    # Build the embedded server
    args << "-DWITH_EMBEDDED_SERVER=ON" if build.include? 'with-embedded'

    # Compile with readline unless libedit is explicitly chosen
    args << "-DWITH_READLINE=yes" unless build.include? 'with-libedit'

    # Make universal for binding to universal applications
    args << "-DCMAKE_OSX_ARCHITECTURES='#{Hardware::CPU.universal_archs.as_cmake_arch_flags}'" if build.universal?

    # Build with local infile loading support
    args << "-DENABLED_LOCAL_INFILE=1" if build.include? 'enable-local-infile'

    system "cmake", *args
    system "make"
    # Reported upstream:
    # http://bugs.mysql.com/bug.php?id=69645
    inreplace "scripts/mysql_config", / +-Wno[\w-]+/, ""
    system "make install"

    # Don't create databases inside of the prefix!
    # See: https://github.com/mxcl/homebrew/issues/4975
    rm_rf prefix+'data'

    # Link the setup script into bin
    ln_s prefix+'scripts/mysql_install_db', bin+'mysql_install_db'

    # Fix up the control script and link into bin
    inreplace "#{prefix}/support-files/mysql.server" do |s|
      s.gsub!(/^(PATH=".*)(")/, "\\1:#{HOMEBREW_PREFIX}/bin\\2")
    end

    ln_s "#{prefix}/support-files/mysql.server", bin

    # Move mysqlaccess to libexec
    mv "#{bin}/mysqlaccess", libexec
    mv "#{bin}/mysqlaccess.conf", libexec
  end

  def caveats; <<-EOS.undent
    Set up databases to run AS YOUR USER ACCOUNT with:
        unset TMPDIR
        mysql_install_db --verbose --user=`whoami` --basedir="$(brew --prefix percona-server)" --datadir=#{var}/#{destination} --tmpdir=/tmp

    To set up base tables in another folder, or use a different user to run
    mysqld, view the help for mysqld_install_db:
        mysql_install_db --help

    and view the MySQL documentation:
      * http://dev.mysql.com/doc/refman/5.5/en/mysql-install-db.html
      * http://dev.mysql.com/doc/refman/5.5/en/default-privileges.html

    To run as, for instance, user "mysql", you may need to `sudo`:
        sudo mysql_install_db ...options...

    A "/etc/my.cnf" from another install may interfere with a Homebrew-built
    server starting up correctly.

    To connect:
        mysql -uroot
    EOS
  end

  plist_options :manual => 'mysql.server start'

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>KeepAlive</key>
      <true/>
      <key>Label</key>
      <string>#{plist_name}</string>
      <key>Program</key>
      <string>#{opt_prefix}/bin/mysqld_safe</string>
      <key>RunAtLoad</key>
      <true/>
      <key>WorkingDirectory</key>
      <string>#{var}</string>
    </dict>
    </plist>
    EOS
  end
end
