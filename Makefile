clean:
	@rm -rf public/*


build: clean
	@hugo --gc --minify


deploy: build
	@rsync -avz --delete public/ lthibau.lt:/home/lthibault/www/lthibau.lt/
