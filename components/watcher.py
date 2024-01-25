# meticulous watcher script for the service
# this Script will handle emergency updates for the backend

from tornado.options import define, options, parse_command_line
import tornado.web
import tornado.ioloop
import hashlib
import os
import subprocess
import threading
import traceback
import socketio

UPDATE_FILE = "/opt/meticulous-update.tar.gz"

# HTTP SERVER HANDLING
class UploadHandler(tornado.web.RequestHandler):
    def set_default_headers(self):
        self.set_header("Access-Control-Allow-Origin", "*")     #allows requests from the dashboard
        self.set_header("Access-Control-Allow-Headers", "x-requested-with, Content-MD5, Content-Length")
        self.set_header('Access-Control-Allow-Methods', 'PUT')

    def put(self):
        received_file = self.request.body
        received_sha = self.request.headers.get('Content-MD5')

        computed_sha = hashlib.sha256(received_file).hexdigest()

        if computed_sha == received_sha:
            self.set_status(200)
            self.write("File received and verified successfully!")
            with open(os.path.expanduser(UPDATE_FILE), 'wb') as file:
                file.write(received_file)

            tr = threading.Thread(target=startUpdate)
            tr.start()
        else:
            self.set_status(400)
            self.write("sha checksum mismatch!")


#This function starts the update process
def startUpdate():

    #extract the directory of the update 
    command = f'sudo tar -xzf {UPDATE_FILE} -C /opt/meticulous-backend'
    subprocess.run(command, shell=True)

    #delete the compressed file
    command = f'sudo rm {UPDATE_FILE}'
    subprocess.run(command, shell=True)

    # restart
    subprocess.run("systemctl restart meticulous-backend",shell=True)

def main():

    parse_command_line()

    sio = socketio.AsyncServer(cors_allowed_origins='*', async_mode='tornado')

    app = tornado.web.Application(
        [
            (r"/update", UploadHandler),
            (r"/socket.io/", socketio.get_tornado_handler(sio)),
            (r'/(.*)', tornado.web.StaticFileHandler, {"default_filename": "index.html","path": os.path.dirname(__file__)+"/meticulous-dashboard"}),
            (r'', tornado.web.RedirectHandler, {"url":"/"}),
        ],
    )

    app.listen(options.port)

    tornado.ioloop.IOLoop.current().start()


#execution phase
define("port", default=3000, help="run on the given port", type=int)

if __name__ == "__main__":
    try:
        main()
    except:
        traceback.print_exc()