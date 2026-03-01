include .env.target
export

.PHONY: deploy
deploy:
	rsync -avP --delete --exclude .git --exclude .DS_Store ./ $(TARGET_HOST):$(TARGET_PATH)/
	ssh $(TARGET_HOST) "cd $(TARGET_PATH) && chmod +x setup-prod.sh && ./setup-prod.sh && docker ps"
