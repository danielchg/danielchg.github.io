.PHONHY: run

run:
	hugo server -

new-entry:
ifndef ENTRY_PATH
	$(error ENTRY_PATH is not set. Usage: make new-entry ENTRY_PATH=content/posts/your-post/index.md)
endif
	hugo new content $(ENTRY_PATH)

