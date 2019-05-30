# distro for package building (oneof: xenial, centos-7-x86_64)
RELEASE               ?= 1802
DISTRIBUTION          ?= none
DOCKER_RELEASE        ?= development
DOCKER_REG_NAME       ?= "docker.onedata.org"
DOCKER_REG_USER       ?= ""
DOCKER_REG_PASSWORD   ?= ""
DOCKER_BASE_IMAGE     ?= "ubuntu:16.04"
DOCKER_DEV_BASE_IMAGE ?= "onedata/worker:1802-1"

PKG_REVISION      ?= $(shell git describe --tags --always)
PKG_VERSION       ?= $(shell git describe --tags --always | tr - .)
ONECLIENT_VERSION ?= $(PKG_VERSION)
PKG_COMMIT        ?= $(shell git rev-parse HEAD)
PKG_BUILD         ?= 1
PKG_ID             = fs-onedatafs-$(PKG_VERSION)

.PHONY: check_distribution
check_distribution:
ifeq ($(DISTRIBUTION), none)
	@echo "Please provide package distribution. Oneof: 'trusty', 'wily', 'xenial', 'centos-7-x86_64', 'fedora-23-x86_64'"
	@exit 1
else
	@echo "Building package for distribution $(DISTRIBUTION)"
endif


.PHONY: readme
readme:
	pandoc --from=markdown --to=rst --output=README.rst README.md

.PHONY: release
release: readme
	python setup.py sdist bdist_wheel

.PHONY: test
test:
	nosetests --with-coverage --cover-erase --logging-level=ERROR --cover-package=fs_onedatafs -a "!slow" fs_onedatafs/tests
	rm .coverage

.PHONY: slowtest
slowtest:
	nosetests --with-coverage --cover-erase --logging-level=ERROR --cover-package=fs_onedatafs fs_onedatafs/tests
	rm .coverage

.PHONY: testall
testall:
	tox

.PHONY: clean
clean:
	python setup.py clean --all
	rm -rf package

.PHONY: docs
docs:
	cd docs && make html
	python -c "import os, webbrowser; webbrowser.open('file://' + os.path.abspath('./docs/_build/html/index.html'))"

package/$(PKG_ID).tar.gz:
	mkdir -p package
	rm -rf package/$(PKG_ID)
	git archive --format=tar --prefix=$(PKG_ID)/ $(PKG_REVISION) | (cd package && tar -xf -)
	find package/$(PKG_ID) -depth -name ".git" -exec rm -rf {} \;
	echo "set(GIT_VERSION ${PKG_REVISION})" > package/$(PKG_ID)/version.txt
	tar -C package -czf package/$(PKG_ID).tar.gz $(PKG_ID)

.PHONY: rpm
rpm: check_distribution package/$(PKG_ID).tar.gz
	rm -rf package/packages && mkdir -p package/packages

	cp pkg_config/fs-onedatafs-py2.spec package/fs-onedatafs-py2.spec
	cp pkg_config/fs-onedatafs-py3.spec package/fs-onedatafs-py3.spec
	cp pkg_config/data/__init__.py package/__init__.py

	patch -d package/ -p1 -i $(PKG_ID)/pkg_config/$(DISTRIBUTION).patch

	sed -i "s/{{version}}/$(PKG_VERSION)/g" package/fs-onedatafs-py2.spec
	sed -i "s/{{onedatafs_version}}/$(ONECLIENT_VERSION)/g" package/fs-onedatafs-py2.spec
	sed -i "s/{{build}}/$(PKG_BUILD)/g" package/fs-onedatafs-py2.spec
	sed -i "s/{{version}}/$(PKG_VERSION)/g" package/fs-onedatafs-py3.spec
	sed -i "s/{{onedatafs_version}}/$(ONECLIENT_VERSION)/g" package/fs-onedatafs-py3.spec
	sed -i "s/{{build}}/$(PKG_BUILD)/g" package/fs-onedatafs-py3.spec

	mock --root $(DISTRIBUTION) --buildsrpm --spec package/fs-onedatafs-py2.spec --resultdir=package/packages \
		--sources package
	mock --root $(DISTRIBUTION) --resultdir=package/packages \
		--rebuild package/packages/onedata$(RELEASE)-python2-$(PKG_ID)*.src.rpm

	mock --root $(DISTRIBUTION) --buildsrpm --spec package/fs-onedatafs-py3.spec --resultdir=package/packages \
		--sources package
	mock --root $(DISTRIBUTION) --resultdir=package/packages \
		--rebuild package/packages/onedata$(RELEASE)-python3-$(PKG_ID)*.src.rpm
