#!/bin/bash

#PREGUNTAR AL USUARIO SOBRE HOST
read -p "Coloca tu dominio: " HOST

#DOMINIO
if [ "$HOST" = "" ]; then
    echo No ha ingresado dominio, vuelva a ejecutar el script agregando un dominio
    exit 1
fi

#PREGUNTAR AL USUARIO SOBRE EL SERVICE NUMBER
read -p "Coloque su numero de servicio para instalar: (presione enter si es la primera instalacion de su servidor) " SERVICE_NUMBER

#NUMERO DE SERVICIO
if [ "$SERVICE_NUMBER" = '' ]; then
        SERVICE_NUMBER="1"
fi

#PORT DE MYSQL
MYSQL_PORT_HOST=$((3000 + $SERVICE_NUMBER))

#VERSION
read -p "indique versión del facturador a instalar, [1](Pro7) [2](ProX) : " version
if [ "$version" = '1' ]; then
    VERSION_PHP_IMAGE="2.0"
    DB_FOLDER="seeds"
    SCHEDULING="scheduling"
    SUPERVISOR="php7.4-supervisor"
    PROYECT='https://github.com/principixz/pro7.git'
elif [ "$version" = '2' ]; then
    VERSION_PHP_IMAGE="8.2"
    DB_FOLDER="seeders"
    SCHEDULING="scheduling:8.2"
    SUPERVISOR="supervisor-php:8.2"
    PROYECT='https://gitlab.buho.la/facturaloperu/facturador/pro-x.git'
else
    echo No ha ingresado una version correcta del facturador
    exit 1
fi

#RUTA DE INSTALACION (RUTA ACTUAL DEL SCRIPT)
PATH_INSTALL=$(echo $PWD)
#NOMBRE DE CARPETA
DIR=$(echo $HOST)
#DATOS DE ACCESO MYSQL
MYSQL_USER=$(echo $DIR)
MYSQL_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')
MYSQL_DATABASE=$(echo $DIR)
MYSQL_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')


if [ "$SERVICE_NUMBER" = '1' ]; then
echo "Actualizando sistema"
apt-get -y update
apt-get -y upgrade

echo "Instalando git"
apt-get -y install git-core

echo "Instalando docker"
apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get -y update
apt-get -y install docker-ce
systemctl start docker
systemctl enable docker

echo "Instalando docker compose"
curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Instalando letsencrypt"
apt-get -y install letsencrypt
mkdir $PATH_INSTALL/certs/

echo "Configurando proxy"
docker network create proxynet
mkdir $PATH_INSTALL/proxy
cat << EOF > $PATH_INSTALL/proxy/docker-compose.yml
version: '3'

services:
    proxy:
        image: rash07/nginx-proxy:2.0
        ports:
            - "80:80"
            - "443:443"
        volumes:
            - ./../certs:/etc/nginx/certs
            - /var/run/docker.sock:/tmp/docker.sock:ro
        restart: always
        privileged: true
networks:
    default:
        external:
            name: proxynet

EOF

cd $PATH_INSTALL/proxy
docker-compose up -d

mkdir $PATH_INSTALL/proxy/fpms
fi

echo "Configurando $DIR"

if ! [ -d $PATH_INSTALL/proxy/fpms/$DIR ]; then
echo "Cloning the repository"
rm -rf "$PATH_INSTALL/$DIR"
git clone "$PROYECT" "$PATH_INSTALL/$DIR"

mkdir $PATH_INSTALL/proxy/fpms/$DIR

#Nombre del DIR parseado
DIR_MODIFIED=$(echo "$DIR" | sed 's/\./_/g')

cat << EOF > $PATH_INSTALL/proxy/fpms/$DIR/default
# Configuración de PHP para Nginx
server {
    listen 80 default_server;
    root /var/www/html/public;
    index index.html index.htm index.php;
    server_name *._;
    charset utf-8;
    server_tokens off;
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    location = /robots.txt {
        log_not_found off;
        access_log off;
    }
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass fpm_$DIR_MODIFIED:9000;
        fastcgi_read_timeout 3600;
    }
    error_page 404 /index.php;
    location ~ /\.ht {
        deny all;
    }
}
EOF



cat << EOF > $PATH_INSTALL/$DIR/docker-compose.yml
version: '3'

services:
    nginx_$SERVICE_NUMBER:
        image: rash07/nginx
        container_name: nginx_$DIR_MODIFIED
        working_dir: /var/www/html
        environment:
            VIRTUAL_HOST: $HOST, *.$HOST
        volumes:
            - ./:/var/www/html
            - $PATH_INSTALL/proxy/fpms/$DIR:/etc/nginx/sites-available
        restart: always
    fpm_$SERVICE_NUMBER:
        image: rash07/php-fpm:$VERSION_PHP_IMAGE
        container_name: fpm_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./ssh:/root/.ssh
            - ./ssh:/var/www/.ssh
            - ./:/var/www/html
        restart: always
    mariadb_$SERVICE_NUMBER:
        image: mariadb:10.5.6
        container_name: mariadb_$DIR_MODIFIED
        environment:
            - MYSQL_USER=\${MYSQL_USER}
            - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
            - MYSQL_DATABASE=\${MYSQL_DATABASE}
            - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
            - MYSQL_PORT_HOST=\${MYSQL_PORT_HOST}
        volumes:
            - mysqldata$SERVICE_NUMBER:/var/lib/mysql
        ports:
            - "\${MYSQL_PORT_HOST}:3306"
        restart: always
    redis_$SERVICE_NUMBER:
        image: redis:alpine
        container_name: redis_$DIR_MODIFIED
        volumes:
            - redisdata$SERVICE_NUMBER:/data
        restart: always
    scheduling_$SERVICE_NUMBER:
        image: rash07/$SCHEDULING
        container_name: scheduling_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
        restart: always
    supervisor_$SERVICE_NUMBER:
        image: rash07/$SUPERVISOR
        container_name: supervisor_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
            - ./supervisor.conf:/etc/supervisor/conf.d/supervisor.conf
        restart: always

networks:
    default:
        external:
            name: proxynet

volumes:
    redisdata$SERVICE_NUMBER:
        driver: "local"
    mysqldata$SERVICE_NUMBER:
        driver: "local"

EOF

cp $PATH_INSTALL/$DIR/.env.example $PATH_INSTALL/$DIR/.env

cat << EOF >> $PATH_INSTALL/$DIR/.env


MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PORT_HOST=$MYSQL_PORT_HOST
EOF

echo "Configurando env"
cd "$PATH_INSTALL/$DIR"

sed -i "/APP_NAME=/c\APP_NAME=$HOST" .env
sed -i "/DB_DATABASE=/c\DB_DATABASE=$MYSQL_DATABASE" .env
sed -i "/DB_PASSWORD=/c\DB_PASSWORD=$MYSQL_ROOT_PASSWORD" .env
sed -i "/DB_HOST=/c\DB_HOST=mariadb_$DIR_MODIFIED" .env
sed -i "/DB_USERNAME=/c\DB_USERNAME=root" .env
sed -i "/APP_URL_BASE=/c\APP_URL_BASE=$HOST" .env
sed -i '/APP_URL=/c\APP_URL=http://${APP_URL_BASE}' .env
sed -i '/FORCE_HTTPS=/c\FORCE_HTTPS=false' .env
sed -i '/APP_DEBUG=/c\APP_DEBUG=false' .env
sed -i '/QUEUE_CONNECTION=/c\QUEUE_CONNECTION=database' .env

ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10 ; echo '')
echo "Configurando archivo para usuario administrador"
mv "$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php" "$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php.bk"


if [ "$version" = '1' ]; then
cat << EOF > $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php
<?php

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     *
     * @return void
     */
    public function run()
    {
        App\Models\System\User::create([
            'name' => 'Admin Instrador',
            'email' => 'admin@$HOST',
            'password' => bcrypt('$ADMIN_PASSWORD'),
        ]);


        DB::table('plan_documents')->insert([
            ['id' => 1, 'description' => 'Facturas, boletas, notas de débito y crédito, resúmenes y anulaciones' ],
            ['id' => 2, 'description' => 'Guias de remisión' ],
            ['id' => 3, 'description' => 'Retenciones'],
            ['id' => 4, 'description' => 'Percepciones']
        ]);

        App\Models\System\Plan::create([
            'name' => 'Ilimitado',
            'pricing' =>  99,
            'limit_users' => 0,
            'limit_documents' =>  0,
            'plan_documents' => [1,2,3,4],
            'locked' => true
        ]);

    }
}

EOF

elif [ "$version" = '2' ]; then

cat << EOF > $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php
<?php

namespace Database\Seeders;

use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Modules\System\Models\Plan;
use Modules\System\Models\User;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     *
     * @return void
     */
    public function run()
    {
        User::query()->create([
            'name' => 'Admin Instrador',
            'email' => 'admin@$HOST',
            'password' => bcrypt('$ADMIN_PASSWORD'),
        ]);

        DB::table('plan_documents')->insert([
            ['id' => 1, 'description' => 'Facturas, boletas, notas de débito y crédito, resúmenes y anulaciones'],
            ['id' => 2, 'description' => 'Guias de remisión'],
            ['id' => 3, 'description' => 'Retenciones'],
            ['id' => 4, 'description' => 'Percepciones']
        ]);

        Plan::query()->create([
            'name' => 'Ilimitado',
            'pricing' => 99,
            'limit_users' => 0,
            'limit_documents' => 0,
            'plan_documents' => [1, 2, 3, 4],
            'locked' => true
        ]);
    }
}
EOF
fi


echo "Configurando proyecto"
docker-compose up -d
docker-compose exec -T fpm_$SERVICE_NUMBER rm composer.lock
docker-compose exec -T fpm_$SERVICE_NUMBER composer self-update
docker-compose exec -T fpm_$SERVICE_NUMBER composer install
docker-compose exec -T fpm_$SERVICE_NUMBER php artisan migrate:refresh --seed
docker-compose exec -T fpm_$SERVICE_NUMBER php artisan key:generate
docker-compose exec -T fpm_$SERVICE_NUMBER php artisan storage:link
docker-compose exec -T fpm_$SERVICE_NUMBER git checkout .
docker-compose exec -T fpm_$SERVICE_NUMBER git config --global core.fileMode false

rm $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php
mv $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php.bk $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php

echo "configurando permisos"
chmod -R 777 "$PATH_INSTALL/$DIR/storage/" "$PATH_INSTALL/$DIR/bootstrap/" "$PATH_INSTALL/$DIR/vendor/"
chmod +x $PATH_INSTALL/$DIR/script-update.sh

echo "configurando Supervisor"
docker-compose exec -T supervisor_$SERVICE_NUMBER service supervisor start
docker-compose exec -T supervisor_$SERVICE_NUMBER supervisorctl reread
docker-compose exec -T supervisor_$SERVICE_NUMBER supervisorctl update
docker-compose exec -T supervisor_$SERVICE_NUMBER supervisorctl start all


#CONFIGURAR CLAVE SSH

read -p "configurar clave SSH para actualización automática? (requiere acceso a https://gitlab.com/profile/keys). si[s] no[n] " ssh
if [ "$ssh" = "s" ]; then


    REMOTE='git@gitlab.com:'$(echo $PROYECT | sed -e s#^https://gitlab.com/##)
    echo "generando clave SSH"
    ssh-keygen -t rsa -q -P "" -f $PATH_INSTALL/$DIR/ssh/id_rsa
    echo "cambiando remote"
    git remote set-url origin $REMOTE

    ssh-keyscan -H gitlab.com >> $PATH_INSTALL/$DIR/ssh/known_hosts

    docker-compose exec -T fpm_$SERVICE_NUMBER chown -R www-data ssh/ /var/www/
fi


#SSL
read -p "instalar SSL gratuito? si[s] no[n]: " ssl
if [ "$ssl" = "s" ]; then

    echo "--IMPORTANTE--"
    echo "--------------"
    echo "Copiar los TXT sin usar [ctrl+c] ya que cancelará el proceso"
    echo "Ingresar correo electronico y aceptar las preguntas"
    echo "--------------"

    certbot certonly --manual -d *.$HOST -d $HOST --agree-tos --no-bootstrap --manual-public-ip-logging-ok --preferred-challenges dns-01 --server https://acme-v02.api.letsencrypt.org/directory


    echo "Configurando certbot"

    if ! [ -f /etc/letsencrypt/live/$HOST/privkey.pem ]; then

        echo "No se ha generado el certificado gratuito"
    else

        sed -i '/APP_URL=/c\APP_URL=https://${APP_URL_BASE}' .env
        sed -i '/FORCE_HTTPS=/c\FORCE_HTTPS=true' .env

        cp /etc/letsencrypt/live/$HOST/privkey.pem $PATH_INSTALL/certs/$HOST.key
        cp /etc/letsencrypt/live/$HOST/fullchain.pem $PATH_INSTALL/certs/$HOST.crt

        docker-compose exec -T fpm_$SERVICE_NUMBER php artisan config:cache
        docker-compose exec -T fpm_$SERVICE_NUMBER php artisan cache:clear

        docker restart proxy_proxy_1

    fi

fi


echo "Ruta del proyecto dentro del servidor: $PATH_INSTALL/$DIR"
echo "----------------------------------------------"
echo "URL: $HOST"
echo "Correo para administrador: admin@$HOST"
echo "Contraseña para administrador: $ADMIN_PASSWORD"
echo "----------------------------------------------"
echo "Acceso remoto a Mysql"
echo "Contraseña para root: $MYSQL_ROOT_PASSWORD"
if [ "$ssh" = "s" ]; then
    echo "----------------------------------------------"
    echo "Clave SSH para añadir en gitlab.com/-/profile/keys"
    cat $PATH_INSTALL/$DIR/ssh/id_rsa.pub
fi

KEY=$(cat $PATH_INSTALL/$DIR/ssh/id_rsa.pub)

cat << EOF > $PATH_INSTALL/$DIR.txt
Ruta del proyecto dentro del servidor: $PATH_INSTALL/$DIR
----------------------------------------------
URL: $HOST
Correo para administrador: admin@$HOST
Contraseña para administrador: $ADMIN_PASSWORD
----------------------------------------------
Acceso remoto a Mysql
Contraseña para root: $MYSQL_ROOT_PASSWORD

----------------------------------------------
Clave SSH para añadir en gitlab.com/-/profile/keys
$KEY

EOF
rm install.sh
else
echo "La carpeta $PATH_INSTALL/proxy/fpms/$DIR ya existe"
fi