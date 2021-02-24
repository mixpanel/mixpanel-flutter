import argparse
import subprocess

parser = argparse.ArgumentParser(description='Release Mixpanel Flutter SDK')
parser.add_argument('--old', help='version for the release', action="store")
parser.add_argument('--new', help='version for the release', action="store")
args = parser.parse_args()

def bump_version():
    replace_version('pubspec.yaml', "version: "  + args.old, "version: " + args.new)
    replace_version('lib/mixpanel_flutter.dart', "\'\\$lib_version\': \'" + args.old + "\'", "\'\\$lib_version\': \'" + args.new + "\'")
    replace_version('test/mixpanel_flutter_test.dart', "\'\\$lib_version\': \'" + args.old + "\'", "\'\\$lib_version\': \'" + args.new + "\'")
    replace_version('ios/mixpanel_flutter.podspec', "= \'" + args.old + "\'", "= \'" + args.new + "\'")
    subprocess.call('git add pubspec.yaml', shell=True)
    subprocess.call('git add lib/mixpanel_flutter.dart', shell=True)
    subprocess.call('git add test/mixpanel_flutter_test.dart', shell=True)
    subprocess.call('git add ios/mixpanel_flutter.podspec', shell=True)
    subprocess.call('git commit -m "Version {}"'.format(args.new), shell=True)
    subprocess.call('git push', shell=True)

def replace_version(file_name, old_version, new_version):
    with open(file_name) as f:
        file_str = f.read()
        assert(old_version in file_str)
        file_str = file_str.replace(old_version, new_version)

    with open(file_name, "w") as f:
        f.write(file_str)

def generate_docs():
    subprocess.call('flutter analyze --no-pub --no-current-package lib', shell=True)
    subprocess.call('dartdoc --output docs', shell=True)
    subprocess.call('git add docs', shell=True)
    subprocess.call('git commit -m "Update docs"', shell=True)
    subprocess.call('git push', shell=True)

def add_tag():
    subprocess.call('git tag -a v{} -m "version {}"'.format(args.new, args.new), shell=True)
    subprocess.call('git push origin --tags', shell=True)

def publish_dry_run():
    subprocess.call('mv docs doc', shell=True)
    subprocess.call('dart pub publish --dry-run', shell=True)
    subprocess.call('mv doc docs', shell=True)

def main():
    bump_version()
    generate_docs()
    add_tag()
    publish_dry_run()
    print("Congratulations! " + args.new + " is now ready to be released!")

if __name__ == '__main__':
    main()
