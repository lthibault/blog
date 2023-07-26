clean:
	@rm -rf public/*


build: clean
	@hugo --gc --minify


deploy: build
	@rsync -avz --delete public/ root@lthibau.lt:/var/www/html/lthibau.lt/
