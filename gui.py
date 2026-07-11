import tkinter as tk
from tkinter import ttk, filedialog, messagebox

from storage import Storage


class ExcelViewer:

    def __init__(self, root, document):

        self.root = root
        self.document = document
        self.storage = Storage()

        self.root.title("Simple Excel Viewer")
        self.root.geometry("900x600")

        # Widgets
        self.tree = None
        self.search_var = tk.StringVar()
        self.new_product_var = tk.StringVar()

        # Build GUI
        self.configure_style()
        self.build_toolbar()
        self.build_tree()

        # Events
        self.search_var.trace_add("write", self.on_search)

        self.root.protocol(
            "WM_DELETE_WINDOW",
            self.on_close
        )

        # Show data if a document was already loaded
        self.refresh_tree()

    def on_open(self):

        filename = filedialog.askopenfilename(
            filetypes=[("Excel files", "*.xlsx")]
        )

        if not filename:
            return

        self.document.load(filename)

        self.refresh_tree()

    def refresh_tree(self, dataframe=None):

        # Use the whole document if no filtered DataFrame is supplied
        if dataframe is None:
            dataframe = self.document.df

        # Nothing loaded
        if dataframe is None:
            return

        # Clear existing rows
        self.tree.delete(*self.tree.get_children())

        # Configure columns
        columns = list(dataframe.columns)

        self.tree["columns"] = columns
        self.tree["show"] = "headings"

        for col in columns:

            self.tree.heading(
                col,
                text=col,
                anchor="center"
            )

            # Determine an appropriate width
            max_len = min(
                dataframe[col]
                    .fillna("")
                    .astype(str)
                    .apply(len)
                    .max(),
                20
            )

            width = max(
                100,
                len(str(col)) * 12,
                max_len * 8
            )

            self.tree.column(
                col,
                width=width,
                minwidth=80,
                stretch=True,
                anchor="center"
            )

        # Insert rows
        self.create_stripes(dataframe)

    def create_stripes(self, dataframe):

        self.tree.tag_configure(
            "even",
            background="#FFFFFF"
        )

        self.tree.tag_configure(
            "odd",
            background="#A0ECF3"
        )

        for display_index, (real_index, row) in enumerate(dataframe.iterrows()):

            tag = "even" if display_index % 2 == 0 else "odd"

            self.tree.insert(
                "",
                "end",
                iid=str(real_index),
                values=list(row),
                tags=(tag,)
            )

    def configure_style(self):

        style = ttk.Style()

        style.configure(
            "Treeview",
            font=("Segoe UI", 10),
            rowheight=28
        )

        style.configure(
            "Treeview.Heading",
            font=("Segoe UI", 10, "bold")
        )

        style.map(
            "Treeview",
            background=[
                ("selected", "#4A90E2")
            ]
        )
    
    def on_sort(self):

        if self.document.df.empty:
            return

        dialog = tk.Toplevel(self.root)
        dialog.title("Sort")
        dialog.resizable(False, False)
        dialog.transient(self.root)
        dialog.grab_set()

        columns = list(self.document.df.columns)

        # Store widgets
        column_boxes = []
        order_boxes = []

        for i in range(3):

            tk.Label(
                dialog,
                text=f"Sort Level {i + 1}:"
            ).grid(
                row=i,
                column=0,
                padx=10,
                pady=5,
                sticky="w"
            )

            column_combo = ttk.Combobox(
                dialog,
                values=[""] + columns,
                state="readonly",
                width=20
            )
            column_combo.grid(
                row=i,
                column=1,
                padx=5,
                pady=5
            )
            column_combo.current(0)

            order_combo = ttk.Combobox(
                dialog,
                values=["Ascending", "Descending"],
                state="readonly",
                width=12
            )
            order_combo.grid(
                row=i,
                column=2,
                padx=5,
                pady=5
            )
            order_combo.current(0)

            column_boxes.append(column_combo)
            order_boxes.append(order_combo)

        def apply_sort():

            sort_rules = []

            for column_box, order_box in zip(column_boxes, order_boxes):

                column = column_box.get()

                if column == "":
                    continue

                sort_rules.append({

                    "column": column,

                    "ascending": order_box.get() == "Ascending"

                })

            if not sort_rules:
                messagebox.showwarning(
                    "Sort",
                    "Please choose at least one column."
                )
                return

            self.document.sort_rules = sort_rules
            self.document.sort(sort_rules)

            self.refresh_tree()

            dialog.destroy()

        tk.Button(
            dialog,
            text="Sort",
            command=apply_sort,
            width=15
        ).grid(
            row=4,
            column=0,
            columnspan=3,
            pady=15
        )

    def on_add_row(self, event = None):

        value = self.new_product_var.get().strip()

        if not value:
            return

        if self.document.add_row(value):

            self.new_product_var.set("")

            self.search_var.set(value)

    # ---------------- Edit ----------------
    def edit_cell(self, event):

        # Get selected row
        item = self.tree.focus()
        if not item:
            return

        # Get clicked column
        column = self.tree.identify_column(event.x)
        if not column:
            return

        col_index = int(column[1:]) - 1
        column_name = self.tree["columns"][col_index]
        row_index = int(item)

        # Cell position
        x, y, w, h = self.tree.bbox(item, column)

        # Current value
        old_value = self.tree.set(item, column_name)

        # Create Entry over the cell
        entry = tk.Entry(self.tree, justify="center")
        entry.insert(0, old_value)
        entry.place(x=x, y=y, width=w, height=h)
        entry.focus()
        entry.select_range(0, tk.END)

        def finish_edit(event=None):

            new_value = entry.get()

            try:
                self.document.update_cell(
                    row_index,
                    column_name,
                    new_value
                )
            except ValueError as e:
                messagebox.showerror(
                    "Invalid Value",
                    str(e)
                )
                return

            entry.destroy()

            # Refresh according to current search
            self.on_search()

        entry.bind("<Return>", finish_edit)
        entry.bind("<FocusOut>", finish_edit)
        entry.bind("<Escape>", lambda e: entry.destroy())
        
    def on_delete_row(self):

        selected = self.tree.selection()

        if not selected:
            return

        row = int(selected[0])

        if not messagebox.askyesno(
            "Delete",
            "Delete selected row?"
        ):
            return

        if self.document.delete_row(row):

            self.refresh_tree()

    def on_search(self, *args):

        if self.document.df.empty:
            return

        text = self.search_var.get()

        filtered_df = self.document.search(text)

        self.refresh_tree(filtered_df)

    def on_close(self):

        self.document.save()

        self.root.destroy()
    
    def build_toolbar(self):

        top = tk.Frame(self.root)
        top.pack(fill="x", padx=5, pady=5)

        tk.Button(
            top,
            text="Open Excel",
            command=self.on_open
        ).pack(side="left")

        tk.Button(
            top,
            text="Save",
            command=self.document.save
        ).pack(side="left", padx=5)

        tk.Label(
            top,
            text="Search:"
        ).pack(side="left", padx=(20, 5))

        tk.Entry(
            top,
            textvariable=self.search_var,
            width=30
        ).pack(side="left")

        tk.Button(
            top,
            text="Sort",
            command=self.on_sort
        ).pack(side="left")

        tk.Button(
            top,
            text="Add Row",
            command=self.on_add_row
        ).pack(side="left", padx=5)

        self.new_product_entry = tk.Entry(
            top,
            textvariable=self.new_product_var,
            width=30
        )
        self.new_product_entry.pack(side="left", padx=5)

        self.new_product_entry.bind("<Return>", self.on_add_row)

        tk.Button(
            top,
            text="Delete Row",
            command=self.on_delete_row
        ).pack(side="left")

    def build_tree(self):

        frame = tk.Frame(self.root)
        frame.pack(fill="both", expand=True)

        self.tree = ttk.Treeview(frame)

        self.tree.pack(
            side="left",
            fill="both",
            expand=True
        )

        vsb = ttk.Scrollbar(
            frame,
            orient="vertical",
            command=self.tree.yview
        )

        vsb.pack(
            side="right",
            fill="y"
        )

        hsb = ttk.Scrollbar(
            self.root,
            orient="horizontal",
            command=self.tree.xview
        )

        hsb.pack(fill="x")

        self.tree.configure(
            yscrollcommand=vsb.set,
            xscrollcommand=hsb.set
        )

        self.tree.bind(
            "<Double-1>",
            self.edit_cell
        )